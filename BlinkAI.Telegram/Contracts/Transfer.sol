// SPDX-License-Identifier: UNLICENSED
// This smart contract code is proprietary.
// Unauthorized copying, modification, or distribution is strictly prohibited.
// For licensing inquiries or permissions, contact info@toolblox.net.
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@tool_blox/contracts/contracts/OwnerPausable.sol";
import "@tool_blox/contracts/contracts/WorkflowBase.sol";
/*
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_fund_transfer
*/
contract TransferWorkflow  is Ownable, ReentrancyGuard, OwnerPausable, WorkflowBase{
	struct Transfer {
		uint id;
		uint64 status;
		address receiver;
		uint amount;
	}
	mapping(uint => Transfer) public items;
	function _assertOrAssignReceiver(Transfer memory item) private view {
		address receiver = item.receiver;
		if (receiver != address(0))
		{
			require(_msgSender() == receiver, "Invalid Receiver");
			return;
		}
		item.receiver = _msgSender();
	}
	constructor() OwnerPausable(_msgSender()) {
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
/*
	Available statuses:
	1 Scheduled
	0 Sent
*/
	function _assertStatus(Transfer memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Transfer memory) {
		Transfer memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Transfer[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Transfer[] memory latestItems = new Transfer[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Transfer[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Transfer[] memory result = new Transfer[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) result[i] = items[ids[i]];
		return result;
	}
	function getId(uint id) public view returns (uint){
		return getItem(id).id;
	}
	function getStatus(uint id) public view returns (uint64){
		return getItem(id).status;
	}
	function getReceiver(uint id) public view returns (address){
		return getItem(id).receiver;
	}
	function getAmount(uint id) public view returns (uint){
		return getItem(id).amount;
	}
/*
	### Transition: 'Send money'
	This transition creates a new object and puts it into `Sent` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Receiver` (Address)
	* `Amount` (Money)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Receiver` (Address)
	* `Amount` (Money)
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Amount` is made from caller to the address specified in the `Receiver` property.
*/
	function sendMoney(address receiver,uint amount) public payable whenNotPaused nonReentrant returns (uint256) {
		uint256 id = _getNextId();
		Transfer memory item;
		item.id = id;
		item.receiver = receiver;
		item.amount = amount;
		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		uint msgValue = msg.value;
		require(
			msgValue >= item.amount,
			"Not enough deposit"
		);
		uint moneyToReturn = msgValue - item.amount;
		if(moneyToReturn > 0)
		{
			payable(_msgSender()).transfer(moneyToReturn);
		}
		if (item.receiver != address(0) && item.amount > 0){
			payable(item.receiver).transfer(item.amount);
		}
		return id;
	}
/*
	### Transition: 'Schedule transfer'
	This transition creates a new object and puts it into `Scheduled` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Receiver` (Address)
	* `Amount` (Money)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Receiver` (Address)
	* `Amount` (Money)
*/
	function scheduleTransfer(address receiver,uint amount) public whenNotPaused nonReentrant returns (uint256) {
		uint256 id = _getNextId();
		Transfer memory item;
		item.id = id;
		item.receiver = receiver;
		item.amount = amount;
		item.status = 1;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'Execute'
	This transition begins from `Scheduled` and leads to the state `Sent`.
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Amount` is made from caller to the address specified in the `Receiver` property.
*/
	function execute(uint256 id) public payable whenNotPaused nonReentrant returns (uint256) {
		Transfer memory item = getItem(id);
		_assertStatus(item, 1);

		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		uint msgValue = msg.value;
		require(
			msgValue >= item.amount,
			"Not enough deposit"
		);
		uint moneyToReturn = msgValue - item.amount;
		if(moneyToReturn > 0)
		{
			payable(_msgSender()).transfer(moneyToReturn);
		}
		if (item.receiver != address(0) && item.amount > 0){
			payable(item.receiver).transfer(item.amount);
		}
		return id;
	}
}