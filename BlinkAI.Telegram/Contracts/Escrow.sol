// SPDX-License-Identifier: UNLICENSED
// This smart contract code is proprietary.
// Unauthorized copying, modification, or distribution is strictly prohibited.
// For licensing inquiries or permissions, contact info@toolblox.net.
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@tool_blox/contracts/contracts/OwnerPausable.sol";
import "@tool_blox/contracts/contracts/WorkflowBase.sol";
/*
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_escrow_contract
*/
contract PaymentWorkflow  is Ownable, AccessControl, ReentrancyGuard, OwnerPausable, WorkflowBase{
	struct Payment {
		uint id;
		uint64 status;
		string name;
		uint price;
		address buyer;
		address seller;
		address arbitrator;
	}
	mapping(uint => Payment) public items;
	function _assertOrAssignBuyer(Payment memory item) private view {
		address buyer = item.buyer;
		if (buyer != address(0))
		{
			require(_msgSender() == buyer, "Invalid Buyer");
			return;
		}
		item.buyer = _msgSender();
	}
	function _assertOrAssignSeller(Payment memory item) private view {
		address seller = item.seller;
		if (seller != address(0))
		{
			require(_msgSender() == seller, "Invalid Seller");
			return;
		}
		item.seller = _msgSender();
	}
	bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
	function _assertOrAssignArbitrator(Payment memory item) private view {
		address arbitrator = item.arbitrator;
		if (arbitrator != address(0))
		{
			require(_msgSender() == arbitrator, "Invalid Arbitrator");
			return;
		}
		_checkRole(ARBITRATOR_ROLE);
		item.arbitrator = _msgSender();
	}
	function addArbitrator(address adr) public returns (address) {
		grantRole(ARBITRATOR_ROLE, adr);
		return adr;
	}
	constructor() OwnerPausable(_msgSender()) {
		_grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
	function transferOwnership(address newOwner) public override onlyOwner {
		require(newOwner != address(0), "New owner is the zero address");    
		revokeRole(DEFAULT_ADMIN_ROLE, owner());
		_transferOwnership(newOwner);
		_grantRole(DEFAULT_ADMIN_ROLE, newOwner);
	}
/*
	Available statuses:
	6 Scheduled
	1 In escrow
	3 Completed
	5 In Arbitrage
*/
	function _assertStatus(Payment memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Payment memory) {
		Payment memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Payment[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Payment[] memory latestItems = new Payment[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Payment[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Payment[] memory result = new Payment[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) result[i] = items[ids[i]];
		return result;
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
	function getPrice(uint id) public view returns (uint){
		return getItem(id).price;
	}
	function getBuyer(uint id) public view returns (address){
		return getItem(id).buyer;
	}
	function getSeller(uint id) public view returns (address){
		return getItem(id).seller;
	}
	function getArbitrator(uint id) public view returns (address){
		return getItem(id).arbitrator;
	}
/*
	### Transition: 'Pay'
	This transition begins from `Scheduled` and leads to the state `In escrow`.
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Buyer` property. If `Buyer` property is not yet set then the method caller becomes the objects `Buyer`.
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Price` is made from caller to the workflow.
*/
	function pay(uint256 id) public payable whenNotPaused nonReentrant returns (uint256) {
		Payment memory item = getItem(id);
		_assertOrAssignBuyer(item);
		_assertStatus(item, 6);

		item.status = 1;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		uint msgValue = msg.value;
		require(
			msgValue >= item.price,
			"Not enough deposit"
		);
		uint moneyToReturn = msgValue - item.price;
		if(moneyToReturn > 0)
		{
			payable(_msgSender()).transfer(moneyToReturn);
		}
		return id;
	}
/*
	### Transition: 'Received release funds'
	This transition begins from `In escrow` and leads to the state `Completed`.
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Buyer` property. If `Buyer` property is not yet set then the method caller becomes the objects `Buyer`.
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Price` is made from workflow to the address specified in the `Seller` property.
*/
	function receivedReleaseFunds(uint256 id) public whenNotPaused nonReentrant returns (uint256) {
		Payment memory item = getItem(id);
		_assertOrAssignBuyer(item);
		_assertStatus(item, 1);

		item.status = 3;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		if (item.seller != address(0) && item.price > 0){
			payable(item.seller).transfer(item.price);
		}
		return id;
	}
/*
	### Transition: 'New escrow'
	This transition creates a new object and puts it into `Scheduled` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Buyer` (Address)
	* `Seller` (Address)
	* `Price` (Money)
	* `Arbitrator` (Whitelisted address)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Buyer` (Address)
	* `Seller` (Address)
	* `Price` (Money)
	* `Arbitrator` (RestrictedAddress)
*/
	function newEscrow(address buyer,address seller,uint price,address arbitrator) public whenNotPaused nonReentrant returns (uint256) {
		uint256 id = _getNextId();
		Payment memory item;
		item.id = id;
		item.buyer = buyer;
		item.seller = seller;
		item.price = price;
		item.arbitrator = arbitrator;
		item.status = 6;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'In dispute'
	This transition begins from `In escrow` and leads to the state `In Arbitrage`.
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Buyer` property. If `Buyer` property is not yet set then the method caller becomes the objects `Buyer`.
*/
	function inDispute(uint256 id) public whenNotPaused nonReentrant returns (uint256) {
		Payment memory item = getItem(id);
		_assertOrAssignBuyer(item);
		_assertStatus(item, 1);

		item.status = 5;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'Decide'
	This transition begins from `In Arbitrage` and leads to the state `Completed`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Payment identifier
	* `Percentage to refund` (Integer)
	
	#### Checks and updates
	The following calculations will be done and updated:
	
	*  `Return to buyer` = `( Price * Percentage to refund ) / 100`
	*  `Return to seller` = `Price - Return to buyer`
	
	#### Payment Process
	At the end of the transition 2 payments are made.
	
	A payment in the amount of `Return to buyer` is made from workflow to the address specified in the `Buyer` property.
	
	A payment in the amount of `Return to seller` is made from workflow to the address specified in the `Seller` property.
*/
	function decide(uint256 id,uint64 percentageToRefund) public whenNotPaused nonReentrant returns (uint256) {
		Payment memory item = getItem(id);
		_assertStatus(item, 5);
		uint returnToBuyer = ( item.price * percentageToRefund ) / 100;
		uint returnToSeller = item.price - returnToBuyer;
		item.status = 3;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		if (item.buyer != address(0) && returnToBuyer > 0){
			payable(item.buyer).transfer(returnToBuyer);
		}
		if (item.seller != address(0) && returnToSeller > 0){
			payable(item.seller).transfer(returnToSeller);
		}
		return id;
	}
}