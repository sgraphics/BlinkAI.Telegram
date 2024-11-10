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
	Toolblox smart-contract workflow: https://app.toolblox.net/summary/blinkai_auction_workflow
	## Summary
	
	> The auction with extending end workflow allows sellers to list items for auction and manage the auction process, while enabling bidders to participate in auctions and place bids on items. The workflow includes provisions for extending the end time of the auction, paying out to the seller if the auction is successful, and allowing the seller to try again or start the auction over if the auction is unsuccessful.
	
	* Seller: A seller could use this workflow to list items for auction and manage the auction process. They would need to provide details about the item, such as its name, description, image, and starting price. They would also need to monitor the auction and decide whether to extend the end time or end the auction early if necessary.
	* Bidder: A bidder could use this workflow to participate in auctions and place bids on items. They would need to review the details of the items being auctioned and decide whether they want to place a bid. They would also need to monitor the auction and decide whether to increase their bid if necessary.
	
	## Benefits
	
	* Trust and transparency: By using a smart contract to manage the auction process, it may be possible to provide a verifiable and immutable record of the bids and auction details. This can help to build trust between the seller and bidders and can provide a transparent and fair process for both parties.
	* Automation and efficiency: A smart contract can automatically execute the rules and conditions of the auction, which can help to streamline the process and reduce the risk of errors or misunderstandings. This can save time and effort for both the seller and bidders and can make the auction platform more efficient to use.
	* Decentralization and censorship-resistance: By using a decentralized platform such as the blockchain to host the auction platform, it may be possible to provide a more censorship-resistant environment for both the seller and bidders. This can be particularly useful for situations where the auction may be controversial or sensitive in nature.
*/
contract ItemWorkflow  is Ownable, ReentrancyGuard, OwnerPausable, WorkflowBase{
	struct Item {
		uint id;
		uint64 status;
		string name;
		uint price;
		string image;
		uint endTime;
		address seller;
		address highestBidder;
	}
	mapping(uint => Item) public items;
	function _assertOrAssignSeller(Item memory item) private view {
		address seller = item.seller;
		if (seller != address(0))
		{
			require(_msgSender() == seller, "Invalid Seller");
			return;
		}
		item.seller = _msgSender();
	}
	function _assertOrAssignHighestBidder(Item memory item) private view {
		address highestBidder = item.highestBidder;
		if (highestBidder != address(0))
		{
			require(_msgSender() == highestBidder, "Invalid Highest bidder");
			return;
		}
		item.highestBidder = _msgSender();
	}
	constructor() OwnerPausable(_msgSender()) {
	}
	function setOwner(address _newOwner) public {
		transferOwnership(_newOwner);
	}
/*
	Available statuses:
	0 Active
	1 Successful
	2 Unsuccessful
*/
	function _assertStatus(Item memory item, uint64 status) private pure {
		require(item.status == status, "Cannot run Workflow action; unexpected status");
	}
	function getItem(uint256 id) public view returns (Item memory) {
		Item memory item = items[id];
		require(item.id == id, "Cannot find item with given id");
		return item;
	}
	function getLatest(uint256 cnt) public view returns(Item[] memory) {
		uint256[] memory latestIds = getLatestIds(cnt);
		Item[] memory latestItems = new Item[](latestIds.length);
		for (uint256 i = 0; i < latestIds.length; i++) latestItems[i] = items[latestIds[i]];
		return latestItems;
	}
	function getPage(uint256 cursor, uint256 howMany) public view returns(Item[] memory) {
		uint256[] memory ids = getPageIds(cursor, howMany);
		Item[] memory result = new Item[](ids.length);
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
	function getImage(uint id) public view returns (string memory){
		return getItem(id).image;
	}
	function getEndTime(uint id) public view returns (uint){
		return getItem(id).endTime;
	}
	function getSeller(uint id) public view returns (address){
		return getItem(id).seller;
	}
	function getHighestBidder(uint id) public view returns (address){
		return getItem(id).highestBidder;
	}
/*
	### Transition: 'Bid up'
	This transition begins from `Active` and leads to the state `Active`.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Id` (Integer) - Item identifier
	* `Bid` (Money)
	
	#### Checks and updates
	The following checks are done before any changes take place:
	
	* The condition ``Bid > Price`` needs to be true or the following error will be returned: *"Needs to be higher"*.
	* The condition ``End time > now`` needs to be true or the following error will be returned: *"Is active"*.
	
	The following calculations will be done and updated:
	
	*  `Previous high bidder` = `Highest bidder`
	*  `Previous high bid` = `Price`
	* `Highest bidder` = `caller`
	* `Price` = `Bid`
	* `End time` = `( ( now + ( 5 * 60 ) ) > End time ) ? ( End time + ( 5 * 60 ) ) : End time`
	
	#### Payment Process
	At the end of the transition 2 payments are made.
	
	A payment in the amount of `Bid` is made from caller to the workflow.
	
	A payment in the amount of `Previous high bid` is made from workflow to the address specified in the `Previous high bidder` property.
*/
	function bidUp(uint256 id,uint bid) public payable whenNotPaused nonReentrant returns (uint256) {
		Item memory item = getItem(id);
		_assertStatus(item, 0);
		require(bid > item.price, "Needs to be higher");
		require(item.endTime > block.timestamp, "Is active");
		address previousHighBidder = item.highestBidder;
		uint previousHighBid = item.price;
		item.highestBidder = _msgSender();
		item.price = bid;
		item.endTime = ( ( block.timestamp + ( 5 * 60 ) ) > item.endTime ) ? ( item.endTime + ( 5 * 60 ) ) : item.endTime;
		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		uint msgValue = msg.value;
		require(
			msgValue >= bid,
			"Not enough deposit"
		);
		uint moneyToReturn = msgValue - bid;
		if(moneyToReturn > 0)
		{
			payable(_msgSender()).transfer(moneyToReturn);
		}
		if (previousHighBidder != address(0) && previousHighBid > 0){
			payable(previousHighBidder).transfer(previousHighBid);
		}
		return id;
	}
/*
	### Transition: 'Create'
	This transition creates a new object and puts it into `Active` state.
	
	#### Transition Parameters
	For this transition, the following parameters are required: 
	
	* `Name` (Text)
	* `Image` (Image)
	* `Price` (Money)
	* `Duration days` (Integer)
	* `Seller` (Address)
	
	#### Checks and updates
	The following properties will be updated on blockchain:
	
	* `Name` (String)
	* `Image` (Image)
	* `Price` (Money)
	* `Seller` (Address)
	
	The following calculations will be done and updated:
	
	* `End time` = `now + ( ( ( Duration days * 60 ) * 60 ) * 24 )`
*/
	function create(string calldata name,string calldata image,uint price,uint64 durationDays,address seller) public whenNotPaused nonReentrant returns (uint256) {
		uint256 id = _getNextId();
		Item memory item;
		item.id = id;
		item.name = name;
		item.image = image;
		item.price = price;
		item.seller = seller;
		item.endTime = block.timestamp + ( ( ( durationDays * 60 ) * 60 ) * 24 );
		item.status = 0;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		return id;
	}
/*
	### Transition: 'End auction'
	This transition begins from `Active` and leads to the state `Successful`. But only if the condition `Price > 0` is true; otherwise it leads to state `Unsuccessful`.
	
	#### Checks and updates
	The following checks are done before any changes take place:
	
	* The condition ``End time < now`` needs to be true or the following error will be returned: *"Has ended"*.
	
	The following calculations will be done and updated:
	
	*  `Payout` = `( End time < now ) ? Price : 0`
	
	#### Payment Process
	In the end a payment is made.
	A payment in the amount of `Payout` is made from workflow to the address specified in the `Seller` property.
*/
	function endAuction(uint256 id) public whenNotPaused nonReentrant returns (uint256) {
		Item memory item = getItem(id);
		_assertStatus(item, 0);
		require(item.endTime < block.timestamp, "Has ended");
		uint payout = ( item.endTime < block.timestamp ) ? item.price : 0;
		item.status = ( item.price > 0 ) ? 1 : 2;
		items[id] = item;
		emit ItemUpdated(id, item.status);
		if (item.seller != address(0) && payout > 0){
			payable(item.seller).transfer(payout);
		}
		return id;
	}
}