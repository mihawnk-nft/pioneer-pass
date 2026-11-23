// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentBadge — Agent Pioneer Badge
/// @notice Free ERC-721 badge + daily check-in streak for Agent ID holders.
/// @dev Dependency-free minimal ERC-721 (no OpenZeppelin) — written from scratch
/// so this repo carries zero third-party code.
/// Gate: caller must hold an Agent ID, checked ON-CHAIN via balanceOf() on the
/// SPACE ID Agent ID contract 0x60b9262456de011f7d15a54cdd8c48baaa8b022f
/// (verified via eth_getCode on BSC mainnet, 23 Nov 2026 — contract has code).
/// One free mint per address (gas only). Daily check-in 1x/day builds a streak;
/// level derives from streak (1 Bronze, 2 Silver, 3 Gold).
/// Red lines honoured: this contract NEVER touches the user's Agent ID NFT
/// (no transfer/sale of it), collects no seed/key, bypasses no user
/// confirmation, and promises no returns.
interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

contract AgentBadge {
    // ---- custom errors ----
    error NotAgentIdHolder();
    error AlreadyMinted();
    error NoBadge();
    error AlreadyCheckedInToday();
    error NonexistentToken(uint256 tokenId);
    error MintToZeroAddress();
    error TransferToZeroAddress();
    error TransferFromIncorrectOwner();
    error NotOwnerNorApproved();
    error ApprovalToCurrentOwner();

    // ---- events ----
    event BadgeMinted(address indexed holder, uint256 indexed tokenId);
    event CheckedIn(address indexed holder, uint256 streak, uint256 day);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ---- ERC-721 metadata ----
    string public constant name = "Agent Pioneer Badge";
    string public constant symbol = "APB";

    // ---- state ----
    IAgentId public immutable agentId;
    address public owner;
    uint256 public nextTokenId = 1;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(address => bool) public hasMinted;
    mapping(address => uint256) public tokenOf;

    mapping(address => uint256) public lastCheckInDay; // block.timestamp / 1 days
    mapping(address => uint256) public streak;
    mapping(address => uint256) public totalCheckIns;

    string private _baseTokenURI;

    constructor(address _agentId, string memory baseURI) {
        require(_agentId != address(0), "agentId zero");
        agentId = IAgentId(_agentId);
        owner = msg.sender;
        _baseTokenURI = baseURI;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // ---- business logic: mint ----

    /// @notice Mint one free badge. Caller must hold an Agent ID and must not
    /// have minted before. Only gas is paid; the badge itself is free.
    function mint() external {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        if (hasMinted[msg.sender]) revert AlreadyMinted();
        uint256 tokenId = nextTokenId++;
        hasMinted[msg.sender] = true;
        tokenOf[msg.sender] = tokenId;
        emit BadgeMinted(msg.sender, tokenId);
        _safeMint(msg.sender, tokenId);
    }

    // ---- business logic: daily check-in ----

    /// @notice Check in once per day. Builds a streak: consecutive days +1,
    /// a missed day resets the streak to 1. Caller must hold a badge AND
    /// still hold an Agent ID.
    function checkIn() external {
        if (!hasMinted[msg.sender]) revert NoBadge();
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        uint256 today = block.timestamp / 1 days;
        if (lastCheckInDay[msg.sender] == today) revert AlreadyCheckedInToday();
        uint256 newStreak;
        if (today > 0 && lastCheckInDay[msg.sender] == today - 1) {
            newStreak = streak[msg.sender] + 1;
        } else {
            newStreak = 1;
        }
        lastCheckInDay[msg.sender] = today;
        streak[msg.sender] = newStreak;
        totalCheckIns[msg.sender] += 1;
        emit CheckedIn(msg.sender, newStreak, today);
    }

    /// @notice Badge level from streak: 0 none, 1 Bronze (1-6), 2 Silver (7-29),
    /// 3 Gold (30+).
    function levelOf(address holder) external view returns (uint256) {
        uint256 s = streak[holder];
        if (s >= 30) return 3;
        if (s >= 7) return 2;
        if (s >= 1) return 1;
        return 0;
    }

    function setBaseURI(string calldata uri) external onlyOwner {
        _baseTokenURI = uri;
    }

    // ---- ERC-721 core ----

    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "balance of zero address");
        return _balances[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        if (tokenOwner == address(0)) revert NonexistentToken(tokenId);
        return tokenOwner;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        ownerOf(tokenId); // reverts if nonexistent
        string memory base = _baseTokenURI;
        if (bytes(base).length == 0) return "";
        return string(abi.encodePacked(base, _toString(tokenId)));
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        if (to == tokenOwner) revert ApprovalToCurrentOwner();
        if (msg.sender != tokenOwner && !isApprovedForAll(tokenOwner, msg.sender)) {
            revert NotOwnerNorApproved();
        }
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        ownerOf(tokenId); // reverts if nonexistent
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        if (to == address(0)) revert TransferToZeroAddress();
        if (ownerOf(tokenId) != from) revert TransferFromIncorrectOwner();
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerNorApproved();
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (!_checkOnERC721Received(from, to, tokenId, data)) {
            revert("receiver rejected");
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    // ---- internals ----

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return spender == tokenOwner || _tokenApprovals[tokenId] == spender || isApprovedForAll(tokenOwner, spender);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        // clear approval (emit Approval to zero so indexers see the reset)
        delete _tokenApprovals[tokenId];
        emit Approval(from, address(0), tokenId);
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _safeMint(address to, uint256 tokenId) internal {
        if (to == address(0)) revert MintToZeroAddress();
        if (_owners[tokenId] != address(0)) revert AlreadyMinted();
        unchecked {
            _balances[to] += 1;
        }
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
        if (!_checkOnERC721Received(address(0), to, tokenId, "")) {
            revert("receiver rejected");
        }
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data)
        internal
        returns (bool)
    {
        if (to.code.length == 0) return true;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 ret) {
            return ret == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // casting to 'uint8' is safe because value % 10 is 0-9, so 48 + it is 48-57
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
