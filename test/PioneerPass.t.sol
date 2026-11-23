// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/PioneerPass.sol";

/// @notice Minimal cheatcode interface, defined locally.
/// No forge-std dependency — this repo carries zero third-party code.
interface Vm {
    function warp(uint256 newTimestamp) external;
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert(bytes4 revertData) external;
}

/// @notice Minimal mock of the Agent ID contract: only balanceOf(), settable.
contract MockAgentId {
    mapping(address => uint256) private _balances;

    function setBalance(address holder, uint256 amount) external {
        _balances[holder] = amount;
    }

    function balanceOf(address holder) external view returns (uint256) {
        return _balances[holder];
    }
}

contract PioneerPassTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    PioneerPass badge;
    MockAgentId agentId;

    address holder = address(0xA11CE);
    address nonHolder = address(0xB0B);
    address stranger = address(0x5EED);

    uint256 constant DAY = 1 days;
    uint256 constant T0 = 1_700_000_000; // fixed start time

    function setUp() public {
        vm.warp(T0);
        agentId = new MockAgentId();
        agentId.setBalance(holder, 1);
        badge = new PioneerPass(address(agentId), "");
    }

    // ---- tiny assertion helpers (no forge-std) ----
    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _eqAddr(address a, address b, string memory m) internal pure {
        require(a == b, m);
    }

    function _eqStr(string memory a, string memory b, string memory m) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), m);
    }

    function _true(bool c, string memory m) internal pure {
        require(c, m);
    }

    // ---- mint gate ----
    function testMint_RevertsForNonHolder() public {
        vm.prank(nonHolder);
        vm.expectRevert(PioneerPass.NotAgentIdHolder.selector);
        badge.mint();
    }

    function testMint_Success() public {
        vm.prank(holder);
        badge.mint();
        _true(badge.hasMinted(holder), "hasMinted");
        _eq(badge.tokenOf(holder), 1, "tokenOf");
        _eq(badge.balanceOf(holder), 1, "balanceOf");
        _eqAddr(badge.ownerOf(1), holder, "ownerOf");
        _eq(badge.nextTokenId(), 2, "nextTokenId");
    }

    function testMint_SecondMintReverts() public {
        vm.prank(holder);
        badge.mint();
        vm.prank(holder);
        vm.expectRevert(PioneerPass.AlreadyMinted.selector);
        badge.mint();
    }

    // ---- check-in ----
    function testCheckIn_RevertsWithoutBadge() public {
        vm.prank(holder); // holds Agent ID but never minted
        vm.expectRevert(PioneerPass.NoBadge.selector);
        badge.checkIn();
    }

    function testCheckIn_Success() public {
        vm.prank(holder);
        badge.mint();
        vm.prank(holder);
        badge.checkIn();
        _eq(badge.streak(holder), 1, "streak 1");
        _eq(badge.totalCheckIns(holder), 1, "totalCheckIns 1");
        _eq(badge.lastCheckInDay(holder), T0 / DAY, "lastCheckInDay");
    }

    function testCheckIn_TwiceSameDayReverts() public {
        vm.prank(holder);
        badge.mint();
        vm.prank(holder);
        badge.checkIn();
        vm.prank(holder);
        vm.expectRevert(PioneerPass.AlreadyCheckedInToday.selector);
        badge.checkIn();
    }

    function testCheckIn_StreakIncrements() public {
        vm.startPrank(holder);
        badge.mint();
        badge.checkIn(); // day 0 -> streak 1
        vm.warp(T0 + 1 * DAY);
        badge.checkIn(); // day 1 -> streak 2
        vm.warp(T0 + 2 * DAY);
        badge.checkIn(); // day 2 -> streak 3
        vm.stopPrank();
        _eq(badge.streak(holder), 3, "streak 3");
        _eq(badge.totalCheckIns(holder), 3, "totalCheckIns 3");
    }

    function testCheckIn_StreakResetsAfterGap() public {
        vm.startPrank(holder);
        badge.mint();
        badge.checkIn(); // day 0 -> streak 1
        vm.warp(T0 + 3 * DAY); // skip 2 days
        badge.checkIn(); // day 3 -> streak resets to 1
        vm.stopPrank();
        _eq(badge.streak(holder), 1, "streak reset to 1");
        _eq(badge.totalCheckIns(holder), 2, "totalCheckIns 2");
    }

    function testCheckIn_RevertsIfAgentIdLost() public {
        vm.prank(holder);
        badge.mint();
        agentId.setBalance(holder, 0); // Agent ID gone
        vm.prank(holder);
        vm.expectRevert(PioneerPass.NotAgentIdHolder.selector);
        badge.checkIn();
    }

    // ---- level ----
    function testLevel_BronzeSilverGold() public {
        vm.startPrank(holder);
        badge.mint();
        _eq(badge.levelOf(holder), 0, "level 0 before check-in");
        badge.checkIn(); // streak 1
        _eq(badge.levelOf(holder), 1, "level 1 Bronze");
        for (uint256 i = 1; i < 7; i++) {
            vm.warp(T0 + i * DAY);
            badge.checkIn();
        }
        _eq(badge.streak(holder), 7, "streak 7");
        _eq(badge.levelOf(holder), 2, "level 2 Silver");
        for (uint256 i = 7; i < 30; i++) {
            vm.warp(T0 + i * DAY);
            badge.checkIn();
        }
        vm.stopPrank();
        _eq(badge.streak(holder), 30, "streak 30");
        _eq(badge.levelOf(holder), 3, "level 3 Gold");
    }

    // ---- ERC-721 basics ----
    function testTransfer_BasicERC721() public {
        vm.prank(holder);
        badge.mint();
        vm.prank(holder);
        badge.transferFrom(holder, stranger, 1);
        _eqAddr(badge.ownerOf(1), stranger, "owner after transfer");
        _eq(badge.balanceOf(holder), 0, "holder balance 0");
        _eq(badge.balanceOf(stranger), 1, "stranger balance 1");
    }

    function testTokenURI() public {
        badge.setBaseURI("https://example.com/badge/");
        vm.prank(holder);
        badge.mint();
        _eqStr(badge.tokenURI(1), "https://example.com/badge/1", "tokenURI");
    }
}
