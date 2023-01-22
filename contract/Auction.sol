//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";
import "./SafeERC20.sol";

enum AuctionType {
    BID,
    FIXED,
    BOTH
}

enum BidType {
    BID,
    BUY_NOW,
    PAY_OVER_TIME // neww bidtype
}

contract Auction {
    //Constants for auction
    enum AuctionState {
        BIDDING,
        NO_BID_CANCELLED,
        SELECTION,
        VERIFICATION,
        CANCELLED,
        COMPLETED
    }

    enum BidState {
        BIDDING,
        PENDING_SELECTION,
        SELECTED,
        REFUNDED,
        CANCELLED,
        DEAL_SUCCESSFUL_PAID,
        DEAL_UNSUCCESSFUL_REFUNDED
    }

    struct Bid {
        uint256 bidAmount;
        uint256 partPayment; //addition
        uint256 bidTime;
        bool isSelected;
        BidState bidState;
    }

    AuctionState public auctionState;
    AuctionType public auctionType;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public minPrice;
    uint256 public fixedPrice;
    int32 public noOfCopies;
    int32 public noOfSpSelected;
    int32 private noOfBidders;

    address[] public bidders;
    mapping(address => Bid) public bids;

    address public admin;
    address public client;
    IERC20 private paymentToken;

    event AuctionCreated(
        address indexed _client,
        uint256 _minPrice,
        uint256 _fixedPrice,
        int32 noOfCopies,
        AuctionState _auctionState,
        AuctionType _type
    );
    event BidPlaced(
        address indexed _bidder,
        uint256 _value,
        BidState _bidState,
        BidType _bidType,
        AuctionType _auctionType
    );
    event BidToppedUP(
        address indexed _bidder,
        uint256 _value,
        BidState _bidState,
        BidType _bidType
    );    
    event BiddingEnded();
    event BidSelected(
        address indexed _bidder,
        uint256 _value,
        int32 _totalNoOfSpSelected
    );
    event SelectionEnded();
    event AuctionCancelled();
    event AuctionCancelledNoBids();
    event BidsUnselectedRefunded(uint32 _count);
    event AllBidsRefunded(uint32 _count);
    event BidDealSuccessfulPaid(address indexed _bidder, uint256 _value);
    event BidDealUnsuccessfulRefund(
        address indexed _bidder,
        uint256 _refundAmount,
        uint256 _paidAmount
    );
    event AuctionEnded();

    constructor(
        IERC20 _paymentToken,
        uint256 _minPrice,
        int32 _noOfCopies,
        address _client,
        address _admin,
        uint256 _fixedPrice,
        uint256 _biddingTime, // unit s;
        AuctionType _type
    ) {
        if (_type != AuctionType.BID) {
            require(_noOfCopies == 1, "noOfCopies should be 1");
        } else {
            require(_noOfCopies > 0, "noOfCopies has to be > 0");
        }
        admin = _admin;
        paymentToken = IERC20(_paymentToken);

        minPrice = _minPrice;
        fixedPrice = _fixedPrice;
        noOfCopies = _noOfCopies;
        auctionState = AuctionState.BIDDING;
        auctionType = _type;
        client = _client;
        startTime = block.timestamp;
        endTime = block.timestamp + _biddingTime;
        emit AuctionCreated(
            client,
            minPrice,
            fixedPrice,
            noOfCopies,
            auctionState,
            auctionType
        );
        console.log("Auction deployed with admin: ", admin);
    }

    //SPs place bid
    function placeBid(uint256 _bid, BidType _bidType) public notExpired {
        uint256 _partPayment;
        require(auctionState == AuctionState.BIDDING, "Auction not BIDDING");
        require(_bid > 0, "Bid not > 0");
        require(getAllowance(msg.sender) > _bid, "Insufficient allowance");
        require(
            _bid < paymentToken.balanceOf(msg.sender),
            "Insufficient balance"
        );
        if (auctionType == AuctionType.FIXED) {
            require(_bidType == BidType.BUY_NOW, "bidType not right");
            bidFixedAuction(_bid);
            return;
        } else if (
            auctionType == AuctionType.BOTH && _bidType == BidType.BUY_NOW
        ) {
            buyWithFixedPrice(_bid);
            return;
            //addition for bid now and pay over time
        } else if (
            auctionType == AuctionType.BOTH || auctionType == AuctionType.BID
        ) {
            require(_bidType == BidType.PAY_OVER_TIME, "bidType not right");
            bidNowAndPayOverTime(_bid, _partPayment);
            return;
            //end of addition for bid now and pay over time
        } 
        // Normal bid function
        Bid storage b = bids[msg.sender];
        require(_bid + b.bidAmount >= minPrice, "Bid total amount < minPrice");

        if (!hasBidded(msg.sender)) {
            bidders.push(msg.sender);
            noOfBidders++;
        }
        paymentToken.transferFrom(msg.sender, address(this), _bid);
        b.bidAmount = _bid + b.bidAmount;
        b.bidTime = block.timestamp;
        b.bidState = BidState.BIDDING;

        emit BidPlaced(msg.sender, _bid, b.bidState, _bidType, auctionType);
    }

    // begin bid now and pay over time
    function bidNowAndPayOverTime(uint256 _bid, uint256 _partPayment) internal {
        Bid storage b = bids[msg.sender];
        require(_bid + b.bidAmount >= minPrice, "bid >= price");
        
        paymentToken.transferFrom(msg.sender, address(this),_partPayment);
        if (!hasBidded(msg.sender)) {
            bidders.push(msg.sender);
            noOfBidders++;
        }
        b.bidAmount = _bid + b.bidAmount;
        b.partPayment = _partPayment + b.partPayment;
        b.bidTime = block.timestamp;
        b.bidState = BidState.BIDDING;

        emit BidPlaced(
            msg.sender,
            _bid,
            b.bidState,
            BidType.PAY_OVER_TIME,
            auctionType
        );
    }
    // end bid now and pay over time

    function endBidding() public onlyAdmin {
        require(auctionState == AuctionState.BIDDING, "Auction not BIDDING");
        for (uint8 i = 0; i < bidders.length; i++) {
            Bid storage b = bids[bidders[i]];
            if (b.bidState != BidState.CANCELLED) {
                auctionState = AuctionState.SELECTION;
                updateAllOngoingBidsToPending();
                emit BiddingEnded();
                return;
            }
        }
        auctionState = AuctionState.NO_BID_CANCELLED;
        emit AuctionCancelledNoBids();
    }

    //Client selectBid
    function selectBid(address selectedAddress) public onlyClientOrAdmin {
        require(
            auctionState == AuctionState.SELECTION,
            "Auction not SELECTION"
        );
        require(noOfCopies > noOfSpSelected, "All copies selected");
        Bid storage b = bids[selectedAddress];
        require(
            b.bidState == BidState.PENDING_SELECTION,
            "Bid not PENDING_SELECTION"
        );
        b.bidState = BidState.SELECTED;
        noOfSpSelected++;
        emit BidSelected(selectedAddress, b.bidAmount, noOfSpSelected);
    }

    //ends the selection phase
    function endSelection() public onlyClientOrAdmin {
        require(
            auctionState == AuctionState.SELECTION,
            "Auction not SELECTION"
        );
        uint256[] memory topBids = new uint256[](bidders.length);
        int256 pendingBidsIdx = 0;
        int32 noOfCopiesRemaining = noOfCopies - noOfSpSelected;

        if (noOfCopiesRemaining > 0) {
            //selection not complete
            if (noOfCopies >= noOfBidders) {
                // if noOfCopies exceed or equals to total number of bidders
                for (uint8 i = 0; i < bidders.length; i++) {
                    Bid storage b = bids[bidders[i]];
                    if (b.bidState == BidState.PENDING_SELECTION) {
                        selectBid(bidders[i]);
                    }
                }
            } else {
                for (uint8 i = 0; i < bidders.length; i++) {
                    // get unselected bidders
                    Bid storage b = bids[bidders[i]];
                    if (b.bidState == BidState.PENDING_SELECTION) {
                        topBids[uint256(pendingBidsIdx)] = b.bidAmount;
                        pendingBidsIdx++;
                    }
                }
                pendingBidsIdx--;
                quickSort(topBids, 0, pendingBidsIdx);

                for (
                    int256 i = pendingBidsIdx - noOfCopiesRemaining + 1;
                    i <= pendingBidsIdx;
                    i++
                ) {
                    uint256 topBidAmount = topBids[uint256(i)];
                    for (uint8 j = 0; j < bidders.length; j++) {
                        Bid storage b = bids[bidders[j]];
                        if (
                            b.bidState == BidState.PENDING_SELECTION &&
                            topBidAmount == b.bidAmount
                        ) {
                            selectBid(bidders[j]);
                        }
                    }
                }
            }
        }

        refundUnsuccessfulBids();
        auctionState = AuctionState.VERIFICATION;
        emit SelectionEnded();
    }

    function cancelAuction() public onlyClientOrAdmin {
        require(
            auctionState == AuctionState.BIDDING ||
                auctionState == AuctionState.SELECTION,
            "Auction not BIDDING/SELECTION"
        );
        auctionState = AuctionState.CANCELLED;
        refundAllBids();
        emit AuctionCancelled();
    }

// Bidder topup additional token
     function topUpBidPayment(address bidder) public {
        Bid storage b = bids[bidder];
           // addition for new feature
        require(
           b.partPayment >  0 && b.partPayment < b.bidAmount,
            "Bid has no Part Payment"
        );
        // bidder has to payup
        paymentToken.transferFrom(msg.sender, address(this), b.bidAmount - b.partPayment);
        b.bidAmount = b.bidAmount;
        b.partPayment = b.partPayment + (b.bidAmount + b.partPayment);
        b.bidTime = block.timestamp;
        b.bidState = BidState.BIDDING;

        noOfSpSelected = 1;
        auctionState = AuctionState.VERIFICATION;

        emit BidToppedUP(
            msg.sender, 
            b.partPayment, 
            b.bidState, 
            BidType.PAY_OVER_TIME
        );    
     }

    //sets bid deal to fail and payout amount
    function refundFailedBid(address bidder, uint256 refundAmount)
        public
        onlyAdmin
    {
        require(
            auctionState == AuctionState.VERIFICATION,
            "Auction not VERIFICATION"
        );
        Bid storage b = bids[bidder];
        require(b.bidState == BidState.SELECTED, "Deal not selected");
        require(refundAmount < b.partPayment, "Refund amount > partpayment");
       // send some payment to Admin
        paymentToken.transfer(admin, b.partPayment - refundAmount);
        // send remaining payment to Bidder
        paymentToken.transfer(bidder, refundAmount);
        b.bidState = BidState.DEAL_UNSUCCESSFUL_REFUNDED;
        updateAuctionEnd();
        emit BidDealUnsuccessfulRefund(
            bidder,
            refundAmount,
            b.partPayment - refundAmount
        );
    }

    function setBidDealSuccess(address bidder) public {
        require(
            auctionState == AuctionState.VERIFICATION,
            "Auction not VERIFICATION"
        );
        Bid storage b = bids[bidder];
        require(b.bidState == BidState.SELECTED, "Deal not selected");
        require(
            msg.sender == admin || msg.sender == bidder,
            "Txn sender not admin or SP"
        );

        paymentToken.transfer(client, b.bidAmount);
        b.bidState = BidState.DEAL_SUCCESSFUL_PAID;
        updateAuctionEnd();
        emit BidDealSuccessfulPaid(bidder, b.bidAmount);
    }

    //sets bid deal to fail and payout amount
    function setBidDealRefund(address bidder, uint256 refundAmount)
        public
        onlyAdmin
    {
        require(
            auctionState == AuctionState.VERIFICATION,
            "Auction not VERIFICATION"
        );
        Bid storage b = bids[bidder];
        require(b.bidState == BidState.SELECTED, "Deal not selected");
        require(refundAmount <= b.bidAmount, "Refund amount > bid amount");
        paymentToken.transfer(bidder, refundAmount);
        paymentToken.transfer(client, b.bidAmount - refundAmount);
        b.bidState = BidState.DEAL_UNSUCCESSFUL_REFUNDED;
        updateAuctionEnd();
        emit BidDealUnsuccessfulRefund(
            bidder,
            refundAmount,
            b.bidAmount - refundAmount
        );
    }

    function getBidAmount(address bidder) public view returns (uint256) {
        return bids[bidder].bidAmount;
    }

    function bidFixedAuction(uint256 _bid) internal {
        require(noOfBidders == 0, "Auction Has bidded");
        require(_bid == fixedPrice, "Price not right");
        paymentToken.transferFrom(msg.sender, address(this), _bid);
        Bid storage b = bids[msg.sender];
        b.isSelected = true;
        b.bidState = BidState.SELECTED;
        b.bidAmount = _bid + b.bidAmount;
        b.bidTime = block.timestamp;
        noOfSpSelected = 1;
        noOfBidders = 1;
        auctionState = AuctionState.VERIFICATION;
        emit BidPlaced(
            msg.sender,
            _bid,
            b.bidState,
            BidType.BUY_NOW,
            auctionType
        );
    }

    function buyWithFixedPrice(uint256 _bid) internal {
        Bid storage b = bids[msg.sender];
        require(_bid + b.bidAmount == fixedPrice, "Total price not right");
        paymentToken.transferFrom(msg.sender, address(this), _bid);
        if (!hasBidded(msg.sender)) {
            bidders.push(msg.sender);
            noOfBidders++;
        }
        b.isSelected = true;
        b.bidState = BidState.SELECTED;
        b.bidAmount = _bid + b.bidAmount;
        b.bidTime = block.timestamp;
        refundOthers(msg.sender);
        noOfSpSelected = 1;
        auctionState = AuctionState.VERIFICATION;
        emit BidPlaced(
            msg.sender,
            _bid,
            b.bidState,
            BidType.BUY_NOW,
            auctionType
        );
    }

    //Helper Functions
    function getAllowance(address sender) public view returns (uint256) {
        return paymentToken.allowance(sender, address(this));
    }

    function hasBidded(address bidder) private view returns (bool) {
        for (uint8 i = 0; i < bidders.length; i++) {
            if (bidders[i] == bidder) {
                return true;
            }
        }
        return false;
    }

    function refundAllBids() internal {
        uint32 count = 0;
        for (uint8 i = 0; i < bidders.length; i++) {
            Bid storage b = bids[bidders[i]];
            if (b.bidAmount > 0) {
                paymentToken.transfer(bidders[i], b.bidAmount);
                b.bidAmount = 0;
                b.bidState = BidState.REFUNDED;
                count++;
            }
        }

        emit AllBidsRefunded(count);
    }

    function refundOthers(address _buyer) internal {
        uint32 count = 0;
        for (uint8 i = 0; i < bidders.length; i++) {
            if (bidders[i] == _buyer) continue;
            Bid storage b = bids[bidders[i]];
            if (b.bidAmount > 0) {
                paymentToken.transfer(bidders[i], b.bidAmount);
                b.bidAmount = 0;
                b.isSelected = false;
                b.bidState = BidState.REFUNDED;
                count++;
            }
        }
        emit BidsUnselectedRefunded(count);
    }

    function updateAllOngoingBidsToPending() internal {
        for (uint8 i = 0; i < bidders.length; i++) {
            Bid storage b = bids[bidders[i]];
            if (b.bidAmount > 0) {
                b.bidState = BidState.PENDING_SELECTION;
            }
        }
    }

    function updateAuctionEnd() internal {
        for (uint8 i = 0; i < bidders.length; i++) {
            Bid storage b = bids[bidders[i]];
            if (
                b.bidState == BidState.PENDING_SELECTION ||
                b.bidState == BidState.SELECTED ||
                b.bidState == BidState.BIDDING
            ) {
                return;
            }
        }
        auctionState = AuctionState.COMPLETED;
        emit AuctionEnded();
    }

    // only refunds bids that are currently PENDING_SELECTION.
    function refundUnsuccessfulBids() internal {
        uint32 count = 0;
        for (uint8 i = 0; i < bidders.length; i++) {
            Bid storage b = bids[bidders[i]];
            if (b.bidState == BidState.PENDING_SELECTION) {
                if (b.bidAmount > 0) {
                    paymentToken.transfer(bidders[i], b.bidAmount);
                    b.bidAmount = 0;
                    b.bidState = BidState.REFUNDED;
                    count++;
                }
            }
        }

        emit BidsUnselectedRefunded(count);
    }

    function quickSort(
        uint256[] memory arr,
        int256 left,
        int256 right
    ) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint256(i)] < pivot) i++;
            while (pivot < arr[uint256(j)]) j--;
            if (i <= j) {
                (arr[uint256(i)], arr[uint256(j)]) = (
                    arr[uint256(j)],
                    arr[uint256(i)]
                );
                i++;
                j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Txn sender not admin");
        _;
    }

    modifier notExpired() {
        require(block.timestamp <= endTime, "Auction expired");
        _;
    }

    modifier onlyClient() {
        require(msg.sender == client, "Txn sender not client");
        _;
    }

    modifier onlyClientOrAdmin() {
        require(
            msg.sender == client || msg.sender == admin,
            "Txn sender not admin or client"
        );
        _;
    }
}

// Write some getters