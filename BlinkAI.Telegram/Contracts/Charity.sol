// SPDX-License-Identifier: UNLICENSED
// This smart contract code is proprietary.
// Unauthorized copying, modification, or distribution is strictly prohibited.
// For licensing inquiries or permissions, contact info@toolblox.net.
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@tool_blox/contracts/contracts/WorkflowBase.sol";
/*
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_chartity_and_donation
*/
contract CharityWorkflow  is Ownable, WorkflowBase{
	struct Charity {
		uint id;
		uint64 status;
	}
	mapping(uint => Charity) public items;
	address _charity;
	function getCharity() public view returns (address) {
		return _charity;
	}
	function setCharity(address charity) public onlyOwner {
		_charity = charity;
	}
	string _name;
	function getName() public view returns (string memory) {
		return _name;
	}
	function setName(string memory name) public onlyOwner {
		_name = name;
	}
	string _logo;
	function getLogo() public view returns (string memory) {
		return _logo;
	}
	function setLogo(string memory logo) public onlyOwner {
		_logo = logo;
	}
	constructor() Ownable(_msgSender()) {
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
/*
	Available statuses:
	0 Active
*/
	function _assertStatus(Charity memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Charity memory) {
		Charity memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Charity[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Charity[] memory latestItems = new Charity[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Charity[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Charity[] memory result = new Charity[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) result[i] = items[ids[i]];
		return result;
	}
	function getId(uint id) public view returns (uint){
		return getItem(id).id;
	}
	function getStatus(uint id) public view returns (uint64){
		return getItem(id).status;
	}
/*
	### Transition: 'Donate'
	This transition begins from `Active` and leads to the state `Active`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Charity identifier
	* `Amount` (Money)
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Amount` is made from caller to the address specified in the `Charity` property.
*/
	function donate(uint256 id,uint amount) public payable returns (uint256) {
		Charity memory item = getItem(id);
		_assertStatus(item, 0);

		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		uint msgValue = msg.value;
		require(
			msgValue >= amount,
			"Not enough deposit"
		);
		uint moneyToReturn = msgValue - amount;
		if(moneyToReturn > 0)
		{
			payable(_msgSender()).transfer(moneyToReturn);
		}
		if (getCharity() != address(0) && amount > 0){
			payable(getCharity()).transfer(amount);
		}
		return id;
	}
/*
	### Transition: 'Create charity'
	This transition creates a new object and puts it into `Active` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Name` (Text)
	* `Logo` (Image)
	* `Charity` (Address)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Name` (String)
	* `Logo` (Image)
	* `Charity` (Address)
*/
	function createCharity(string calldata name,string calldata logo,address charity) public returns (uint256) {
		uint256 id = _getNextId();
		Charity memory item;
		item.id = id;
		_name = name;
		_logo = logo;
		_charity = charity;
		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
}