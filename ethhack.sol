pragma solidity 0.8.17;

// ----------------------------------------------------------------------------
// NFT token split contract 
// ----------------------------------------------------------------------------
// SPDX-License-Identifier: MIT
// ----------------------------------------------------------------------------

interface ERC721Interface {
  function safeTransferFrom(address from, address to, uint256 tokenId) external;
  function tokenURI(uint256 tokenId) external view returns (string memory);
  function symbol() external view returns (string memory);
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

interface ERC20Interface {
    function totalSupply() external view returns (uint);
    function balanceOf(address tokenOwner) external view returns (uint);
    function burnAll(address owner) external returns (bool success);
    function mint(address tokenAddress, uint256 tokens) external returns (bool success);
}

contract Owned {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
}

// ----------------------------------------------------------------------------
// ERC20 Token 
// ----------------------------------------------------------------------------
contract ERC20 is Owned {
    string public symbol;
    string public name;
    uint256 _totalSupply;
    uint8 public decimals;
    address public ERC721tokenCONTRACT;
    uint256 public ERC721tokenID;
    string public ERC721tokenURI;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;
    
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

    constructor(string memory _symbol, 
                string memory _name, 
                address _contractAddress, 
                uint256 _tokenId, 
                string memory _tokenURI, 
                uint8 _decimals) {
        symbol = _symbol;
        name = _name;
        ERC721tokenCONTRACT = _contractAddress;
        ERC721tokenID = _tokenId;
        ERC721tokenURI = _tokenURI;
        decimals = _decimals;
    }

    function totalSupply() external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address tokenOwner) external view returns (uint balance) {
        return balances[tokenOwner];
    }

    function transfer(address to, uint tokens) external returns (bool success) {
        require(tokens <= balances[msg.sender]);
        require(to != address(0));
        _transfer(msg.sender, to, tokens);
        return true;
    }

    function _transfer(address from, address to, uint256 tokens) internal {
        balances[from] -= tokens;
        balances[to] += tokens;
        emit Transfer(from, to, tokens);
    }

    function approve(address spender, uint tokens) external returns (bool success) {
        _approve(msg.sender, spender, tokens);
        return true;
    }

    function increaseAllowance(address spender, uint addedTokens) external returns (bool success) {
        _approve(msg.sender, spender, allowed[msg.sender][spender] + addedTokens);
        return true;
    }

    function decreaseAllowance(address spender, uint subtractedTokens) external returns (bool success) {
        _approve(msg.sender, spender, allowed[msg.sender][spender] - subtractedTokens);
        return true;
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0));
        require(spender != address(0));
        allowed[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function transferFrom(address from, address to, uint tokens) external returns (bool success) {
        require(to != address(0));
        _approve(from, msg.sender, allowed[from][msg.sender] - tokens);
        _transfer(from, to, tokens);
        return true;
    }

    function allowance(address tokenOwner, address spender) external view returns (uint remaining) {
        return allowed[tokenOwner][spender];
    }

    function burn(uint tokens) public returns (bool success) {
        require(tokens <= balances[msg.sender]);
        balances[msg.sender] -= tokens;
        _totalSupply -= tokens;
        emit Transfer(msg.sender, address(0), tokens);
        return true;
    }

    function mint(address tokenAddress, uint256 tokens) external onlyOwner returns (bool success) {
        balances[tokenAddress] = balances[tokenAddress] + tokens;
        _totalSupply += tokens;
        emit Transfer(address(0), tokenAddress, tokens);
        return true;
    } 

    function multiTransfer(address[] memory to, uint[] memory values) external returns (uint) {
        require(to.length == values.length);
        uint sum;
        for (uint j; j < values.length; j++) {
            sum += values[j];
        }
        require(sum <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender] - sum;
        for (uint i; i < to.length; i++) {
            balances[to[i]] += values[i];
            emit Transfer(msg.sender, to[i], values[i]);
        }
        return to.length;
    }
}

// ----------------------------------------------------------------------------
// NFT Split 
// ----------------------------------------------------------------------------
contract ERC721Split { 
    string name = "WERC721";
    address erc20contract;

    event Split(address indexed contractAddress, uint256 indexed tokenId, address indexed ercAddress, uint256 time);
    event Constructor(address ERC20contractAddress, string _symbol, string _name, address _contractAddress, uint256 _tokenId, string _tokenURI, uint8 _decimals);
    
    struct SplitInfo {
        address contract721;
        uint256 tokenId;
    }

    mapping(address => SplitInfo) ByERC20contract;
    mapping(address => mapping(uint256 => address)) public getERC20contract;

    constructor() {}

    function fragmentation(address _contractAddress, uint256 _tokenId, uint256 _splitAmount, uint8 _decimals) external returns (address ERC20contract) { 
        require(_splitAmount != 0, 'Split amount cannot be zero.');
        ERC721Interface(_contractAddress).safeTransferFrom(msg.sender, address(this), _tokenId);
        if (getERC20contract[_contractAddress][_tokenId] == address(0)) { // CREATE2
            bytes memory bytecode = abi.encodePacked(type(ERC20).creationCode, abi.encode(
                ERC721Interface(_contractAddress).symbol(), 
                name, 
                _contractAddress, 
                _tokenId, 
                ERC721Interface(_contractAddress).tokenURI(_tokenId), 
                _decimals));
            bytes32 salt = keccak256(abi.encodePacked(_contractAddress, _tokenId, address(this)));
            erc20contract = deploy(bytecode, salt);
            emit Constructor(erc20contract, ERC721Interface(_contractAddress).symbol(), name, _contractAddress, _tokenId, ERC721Interface(_contractAddress).tokenURI(_tokenId), _decimals);
        } else {
            erc20contract = getERC20contract[_contractAddress][_tokenId];
        }
        require(ERC20Interface(erc20contract).mint(msg.sender, _splitAmount));
        ByERC20contract[erc20contract].contract721 = _contractAddress;
        ByERC20contract[erc20contract].tokenId = _tokenId;
        getERC20contract[_contractAddress][_tokenId] = erc20contract;
        emit Split(_contractAddress, _tokenId, erc20contract, block.timestamp);
        return erc20contract;
    }

    function defragmentation(address _ERC20contract) external returns (bool success) {
        require(ERC20Interface(_ERC20contract).balanceOf(msg.sender) == ERC20Interface(_ERC20contract).totalSupply(), "You must own all ERC20 tokens.");
        require(ERC20Interface(_ERC20contract).burnAll(msg.sender));
        ERC721Interface(ByERC20contract[_ERC20contract].contract721).safeTransferFrom(address(this), msg.sender, ByERC20contract[_ERC20contract].tokenId);
        return true;
    }

    function deploy(bytes memory code, bytes32 salt) internal returns (address addr) {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
            }
        }

    function getERC721contract(address ERC20contract) external view returns (address contract721, uint256 tokenId) {
        return (ByERC20contract[ERC20contract].contract721, ByERC20contract[ERC20contract].tokenId);
    }

    function onERC721Received(address, address, uint256, bytes memory) external virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}