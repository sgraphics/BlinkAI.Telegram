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
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_rental_contract
	**Simplified Rental Smart Contract Workflow Description**
	
	### Overview:
	
	This workflow delineates a straightforward rental process on a blockchain. By utilizing smart contracts, it ensures a transparent, automated, and secure rental transaction between the renter and the owner.
	
	### Use Cases:
	
	1.  **Registering an Item for Rent**:
	    
	    *   The owner can register an item for rent by providing its name and daily rental price.
	    *   Only the owner has the authority to register an item.
	2.  **Initiating the Rental Process**:
	    
	    *   A renter can begin the rental by specifying the number of days they intend to rent and the allowance they're willing to pay.
	    *   The start time of the rental is automatically recorded.
	    *   The renter's allowance is validated against the product of the number of days and the daily rental price.
	3.  **Charging During the Rental Period**:
	    
	    *   The owner can charge the renter based on the days the item has been rented.
	    *   The days to be charged are determined by the difference between the current time and the start time of the rental.
	    *   The leftover charge is calculated by multiplying the days to charge with the daily rental price.
	4.  **Updating Rental Details**:
	    
	    *   The owner can update the item's details, such as its name and daily rental price, when it's available.
	    *   The renter can update the allowance while the item is in use.
	5.  **Concluding the Rental Process**:
	    
	    *   The owner can conclude the rental process.
	    *   Any nominal fees are calculated based on the difference between the number of days the item was rented and the days charged.
	    *   The end time of the rental is automatically determined.
	    *   The leftover charge is adjusted based on any overtime.
	6.  **Deactivating an Item**:
	    
	    *   The owner can deactivate an item, moving it to an 'Inactive' state.
	    *   Only the owner has the authority to deactivate an item.
	
	### Why a Simplified Rental Smart Contract is Beneficial:
	
	1.  **Transparency**: Every transaction and state change in the rental process is recorded on the blockchain, ensuring visibility for both parties.
	    
	2.  **Security**: The use of smart contracts ensures that the terms of the rental are adhered to, minimizing potential disputes.
	    
	3.  **Automation**: The smart contract handles calculations, validations, and state transitions, reducing manual interventions and errors.
	    
	4.  **Efficiency**: Immediate settlements and updates are possible through the blockchain, eliminating delays and enhancing the user experience.
	    
	
	In summary, this simplified smart contract for rentals offers a streamlined and transparent approach, ensuring a smooth rental experience for both the owner and the renter, with the added flexibility of deactivating items when needed.
*/
contract RentalWorkflow  is Ownable, ReentrancyGuard, OwnerPausable, WorkflowBase{
	struct Rental {
		uint id;
		string name;
		address renter;
		uint startTime;
		uint daysCharged;
		uint leftoverCharge;
		uint64 numberOfDays;
		uint64 status;
		string image;
		uint price;
		address itemOwner;
	}
	mapping(uint => Rental) public items;
	address public token = 0xfe4F5145f6e09952a5ba9e956ED0C25e3Fa4c7F1;
	function _assertOrAssignRenter(Rental memory item) private view {
		address renter = item.renter;
		if (renter != address(0))
		{
			require(_msgSender() == renter, "Invalid Renter");
			return;
		}
		item.renter = _msgSender();
	}
	function _assertOrAssignItemOwner(Rental memory item) private view {
		address itemOwner = item.itemOwner;
		if (itemOwner != address(0))
		{
			require(_msgSender() == itemOwner, "Invalid Item owner");
			return;
		}
		item.itemOwner = _msgSender();
	}
	constructor() OwnerPausable(_msgSender()) {
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
/*
	Available statuses:
	3 Available
	1 In use
	5 Completed
	6 Inactive
*/
	function _assertStatus(Rental memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Rental memory) {
		Rental memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Rental[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Rental[] memory latestItems = new Rental[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Rental[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Rental[] memory result = new Rental[](ids.length);
		for (uint256 i = 0; i < ids.length; i++) result[i] = items[ids[i]];
		return result;
	}
	function getId(uint id) public view returns (uint){
		return getItem(id).id;
	}
	function getName(uint id) public view returns (string memory){
		return getItem(id).name;
	}
	function getRenter(uint id) public view returns (address){
		return getItem(id).renter;
	}
	function getStartTime(uint id) public view returns (uint){
		return getItem(id).startTime;
	}
	function getDaysCharged(uint id) public view returns (uint){
		return getItem(id).daysCharged;
	}
	function getLeftoverCharge(uint id) public view returns (uint){
		return getItem(id).leftoverCharge;
	}
	function getNumberOfDays(uint id) public view returns (uint64){
		return getItem(id).numberOfDays;
	}
	function getStatus(uint id) public view returns (uint64){
		return getItem(id).status;
	}
	function getImage(uint id) public view returns (string memory){
		return getItem(id).image;
	}
	function getPrice(uint id) public view returns (uint){
		return getItem(id).price;
	}
	function getItemOwner(uint id) public view returns (address){
		return getItem(id).itemOwner;
	}
/*
	### Transition: 'Start rent'
	This transition begins from `Available` and leads to the state `In use`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Rental identifier
	* `Number of days` (Integer)
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Renter` property. If `Renter` property is not yet set then the method caller becomes the objects `Renter`.
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Number of days` (Integer)
	
	The following calculations will be done and updated:
	
	* `Start time` = `now`
*/
	function startRent(uint256 id,uint64 numberOfDays) public whenNotPaused nonReentrant returns (uint256) {
		Rental memory item = getItem(id);
		_assertOrAssignRenter(item);
		_assertStatus(item, 3);
		item.numberOfDays = numberOfDays;
		item.startTime = block.timestamp;
		item.status = 1;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'Pay'
	This transition begins from `In use` and leads to the state `In use`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Rental identifier
	* `Payment` (Money)
	
	#### Access Restrictions
	Access is exclusively limited to the owner of the workflow.
	
	#### Checks and updates
	The following calculations will be done and updated:
	
	*  `Days to charge` = `( ( now - Start time ) / ( ( 24 * 60 ) * 60 ) ) - Days charged`
	* `Days charged` = `Days charged + Days to charge`
	* `Leftover charge` = `Days to charge * Price`
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Leftover charge` is made from caller to the workflow owner.
*/
	function pay(uint256 id,uint /*payment*/) public onlyOwner whenNotPaused nonReentrant returns (uint256) {
		Rental memory item = getItem(id);
		_assertStatus(item, 1);
		uint daysToCharge = ( ( block.timestamp - item.startTime ) / ( ( 24 * 60 ) * 60 ) ) - item.daysCharged;
		item.daysCharged = item.daysCharged + daysToCharge;
		item.leftoverCharge = daysToCharge * item.price;
		item.status = 1;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		if (owner() != address(0) && item.leftoverCharge > 0){
			safeTransferFromExternal(token, _msgSender(), owner(), item.leftoverCharge);
		}
		return id;
	}
/*
	### Transition: 'Register item'
	This transition creates a new object and puts it into `Available` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Name` (Text)
	* `Price` (Money)
	* `Image` (Image)
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Item owner` property. If `Item owner` property is not yet set then the method caller becomes the objects `Item owner`.
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Name` (String)
	* `Price` (Money)
	* `Image` (Image)
*/
	function registerItem(string calldata name,uint price,string calldata image) public whenNotPaused nonReentrant returns (uint256) {
		uint256 id = _getNextId();
		Rental memory item;
		item.id = id;
		_assertOrAssignItemOwner(item);
		item.name = name;
		item.price = price;
		item.image = image;
		item.status = 3;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'Update'
	This transition begins from `Available` and leads to the state `Available`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Rental identifier
	* `Name` (Text)
	* `Price` (Money)
	* `Image` (Image)
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Item owner` property. If `Item owner` property is not yet set then the method caller becomes the objects `Item owner`.
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Name` (String)
	* `Price` (Money)
	* `Image` (Image)
*/
	function update(uint256 id,string calldata name,uint price,string calldata image) public whenNotPaused nonReentrant returns (uint256) {
		Rental memory item = getItem(id);
		_assertOrAssignItemOwner(item);
		_assertStatus(item, 3);
		item.name = name;
		item.price = price;
		item.image = image;
		item.status = 3;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'End and settle'
	This transition begins from `In use` and leads to the state `Completed`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Rental identifier
	* `Payment` (Money)
	
	#### Access Restrictions
	Access is exclusively limited to the owner of the workflow.
	
	#### Checks and updates
	The following calculations will be done and updated:
	
	*  `Nominal fee` = `( Number of days - Days charged ) * Price`
	*  `End time` = `Start time + ( ( ( Number of days * 24 ) * 60 ) * 60 )`
	* `Leftover charge` = `Nominal fee + ( ( now > End time ) ? ( ( End time - now ) * ( ( ( Price / 24 ) / 60 ) / 60 ) ) : 0 )`
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Leftover charge` is made from caller to the workflow owner.
*/
	function endAndSettle(uint256 id,uint /*payment*/) public onlyOwner whenNotPaused nonReentrant returns (uint256) {
		Rental memory item = getItem(id);
		_assertStatus(item, 1);
		uint nominalFee = ( item.numberOfDays - item.daysCharged ) * item.price;
		uint endTime = item.startTime + ( ( ( item.numberOfDays * 24 ) * 60 ) * 60 );
		item.leftoverCharge = nominalFee + ( ( block.timestamp > endTime ) ? ( ( endTime - block.timestamp ) * ( ( ( item.price / 24 ) / 60 ) / 60 ) ) : 0 );
		item.status = 5;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		if (owner() != address(0) && item.leftoverCharge > 0){
			safeTransferFromExternal(token, _msgSender(), owner(), item.leftoverCharge);
		}
		return id;
	}
/*
	### Transition: 'Deactivate'
	This transition begins from `Available` and leads to the state `Inactive`.
	
	#### Access Restrictions
	Access is specifically restricted to the user with the address from the `Item owner` property. If `Item owner` property is not yet set then the method caller becomes the objects `Item owner`.
*/
	function deactivate(uint256 id) public whenNotPaused nonReentrant returns (uint256) {
		Rental memory item = getItem(id);
		_assertOrAssignItemOwner(item);
		_assertStatus(item, 3);

		item.status = 6;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
}