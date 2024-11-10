// SPDX-License-Identifier: UNLICENSED
// This smart contract code is proprietary.
// Unauthorized copying, modification, or distribution is strictly prohibited.
// For licensing inquiries or permissions, contact info@toolblox.net.
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@tool_blox/contracts/contracts/OwnerPausable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@tool_blox/contracts/contracts/WorkflowBase.sol";
/*
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_nft_flow_simple
*/
contract NftWorkflow  is Ownable, OwnerPausable, ERC721Pausable, ERC721Enumerable, WorkflowBase{
	struct Nft {
		uint id;
		uint64 status;
		string name;
		string image;
		string description;
		address owner;
	}
	mapping(uint => Nft) public items;
	function _assertOrAssignOwner(Nft memory item) private view {
		address owner = item.owner;
		if (owner != address(0))
		{
			require(_msgSender() == owner, "Invalid Owner");
			return;
		}
		item.owner = _msgSender();
	}
	constructor() ERC721("NFT", "AINFT") OwnerPausable(_msgSender()) {
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
/*
	Available statuses:
	0 Minted (owner Owner)
*/
	function _assertStatus(Nft memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Nft memory) {
		Nft memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Nft[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Nft[] memory latestItems = new Nft[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Nft[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Nft[] memory result = new Nft[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) result[i] = items[ids[i]];
		return result;
	}
	function getItemOwner(Nft memory item) private view returns (address itemOwner) {
				if (item.status == 0) {
			itemOwner = item.owner;
		}
        else {
			itemOwner = address(this);
        }
        if (itemOwner == address(0))
        {
            itemOwner = address(this);
        }
	}
	function _update(address to, uint256 tokenId, address auth) internal virtual override(ERC721Pausable,ERC721Enumerable) whenNotPaused returns (address) {
		address from = super._update(to, tokenId, auth);
		if (from == to)
		{
			return from;
		}
		Nft memory item = getItem(tokenId);
		bool ownerUpdated = from == address(0);
		if (item.status == 0 && item.owner != to) {
			item.owner = to;
			ownerUpdated = true;
		}
		if (ownerUpdated)
		{
			items[tokenId] = item;
			emit ItemUpdated(tokenId, item.status);
		}
		return from;
	}
    function _increaseBalance(address account, uint128 amount) internal virtual override(ERC721,ERC721Enumerable) {
        super._increaseBalance(account, amount);
    }
	function _baseURI() internal view virtual override returns (string memory) {
		return _baseUri;
	}
	function tokenURI(uint256 tokenId) public view override returns (string memory) {
		if (bytes(_baseUri).length > 0)
		{
			return string.concat(_baseUri, Strings.toString(tokenId));
		} else {
			Nft memory item = getItem(tokenId);
			string memory url = string.concat(string.concat("{\"name\": \"", item.name), "\"");
			url = string.concat(url, string.concat(string.concat(", \"description\": \"", item.description), "\""));
			if (bytes(item.image).length != 0)
			{
				url = string.concat(string.concat(url, ", \"image\": \"https://", item.image), ".ipfs.w3s.link\"");
			}
			url = string.concat(url, ", \"attributes\":[");
			url = string.concat(string.concat(url, " { \"trait_type\" : \"Status\", \"value\" :"),  (item.status == 0 ? "\"Minted\"}" : "\"\"}"));
			url = string.concat(url, string.concat(string.concat(",  { \"trait_type\" : \"Owner\", \"value\" : \"", Strings.toHexString(uint160(item.owner), 20)), "\"}"));
			url = string.concat(url, "]");
			return string.concat("data:application/json;utf8,", string.concat(url, "}"));
		}
	}
	string private _baseUri;
	function setBaseURI(string memory baseUri) external {
		_baseUri = baseUri;
	}
	function supportsInterface(bytes4 interfaceId) public view override(ERC721,ERC721Enumerable) returns (bool) {
		return super.supportsInterface(interfaceId);
	}
	function getId(uint id) public view returns (uint){
		return getItem(id).id;
	}
	function getStatus(uint id) public view returns (uint64){
		return getItem(id).status;
	}
	function getName(uint id) public view returns (string memory){
		return getItem(id).name;
	}
	function getImage(uint id) public view returns (string memory){
		return getItem(id).image;
	}
	function getDescription(uint id) public view returns (string memory){
		return getItem(id).description;
	}
	function getOwner(uint id) public view returns (address){
		return getItem(id).owner;
	}
/*
	### Transition: 'Mint'
	This transition creates a new object and puts it into `Minted` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Name` (Text)
	* `Image` (Image)
	* `Description` (Text)
	* `Owner` (Address)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Name` (String)
	* `Image` (Image)
	* `Description` (String)
	* `Owner` (Address)
*/
	function mint(string calldata name,string calldata image,string calldata description,address owner) public whenNotPaused returns (uint256) {
		uint256 id = _getNextId();
		Nft memory item;
		item.id = id;
		item.name = name;
		item.image = image;
		item.description = description;
		item.owner = owner;
		item.status = 0;
		items[id] = item;
		address newOwner = getItemOwner(item);
		_safeMint(newOwner, id);
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'Transfer'
	This transition begins from `Minted` and leads to the state `Minted`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - NFT identifier
	* `Owner` (Address)
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Owner` property. If `Owner` property is not yet set then the method caller becomes the objects `Owner`.
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Owner` (Address)
*/
	function transfer(uint256 id,address owner) public whenNotPaused returns (uint256) {
		Nft memory item = getItem(id);
		address oldOwner = getItemOwner(item);
		_assertOrAssignOwner(item);
		_assertStatus(item, 0);
		item.owner = owner;
		item.status = 0;
		items[id] = item;
		address newOwner = getItemOwner(item);
		if (newOwner != oldOwner) {
			_transfer(oldOwner, newOwner, id);
		}
		emit ItemUpdated(id, item.status);
		return id;
	}
}