// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "./interface/IPubSubMgr.sol";

contract Broker is
    Initializable,
    IERC721ReceiverUpgradeable,
    IERC1155ReceiverUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    enum OrderStatus {
        NONEXIST,
        LISTED,
        MORTGAGED,
        CLEARING,
        CLAIMABLE,
        CANCELED,
        REPAID,
        CLAIMED
    }

    ///@notice Lender detail
    ///@param price lender offer price
    ///@param interest lender offer interest
    struct Offer {
        uint256 price;
        uint256 interest;
    }

    ///@notice Vendee detail
    ///@param vendee vendee address
    ///@param price vendee offer price
    struct VendeeDetail {
        address vendee;
        uint256 price;
    }

    ///@notice Order detail
    struct OrderDetail {
        address pledger;
        Offer listOffer;
        uint256 duration;
        address lender;
        Offer dealOffer;
        uint256 dealTime;
        VendeeDetail vendee;
        OrderStatus status;
        address nftAddress;
        uint256[] tokenIds;
        uint256[] amounts;
        uint256 nftType; //721, 1155
        EnumerableSetUpgradeable.AddressSet lendersAddress;
        mapping(address => Offer) lenders;
    }

    uint256 public counter;

    ///@notice usdxc token
    address public usdxc;

    ///@notice admin
    address public admin;

    ///@notice platform beneficiary address
    address public beneficiary;

    ///@notice Redemption time period
    uint256 public redemptionPeriod;

    ///@notice clearing time period
    uint256 public clearingPeriod;

    ///@notice Repay interest platform commission（base 1000）
    uint256 public repayInterestCut;

    ///@notice Auction interest pledger commission
    uint256 public auctionPledgerCut;

    ///@notice Auction interest platform commission
    uint256 public auctionDevCut;

    ///@dev Order details list
    mapping(uint256 => OrderDetail) orders;

    ///@notice To prevent malicious attacks, the maximum number of lenderAddresses for each NFT contract. After exceeding the maximum threshold, lenderOffer is not allowed, and 0 means no limit
    // NFT address => maximum offers
    mapping(address => uint256) public maxLendersCnt;
    ///@notice The default value of the maximum number of lenderAddresses per NFT.
    uint256 public defaultMaxLendersCnt;

    address public pendingBeneficiary;

    uint256 public constant MAX_REPAY_INTEREST_CUT = 1000;

    uint256 public constant MAX_REPAY_INTEREST_PLATFORM_CUT = 200;

    uint256 public constant MAX_AUCTION_PLEDGER_CUT = 50;
    uint256 public constant MAX_AUCTION_PLATFORM_CUT = 200;

    // pubSubMgr contract
    address public pubSubMgr;

    ///@notice pledger maker order
    event Pledged(
        uint256 orderId,
        address nftAddress,
        uint256 nftType,
        uint256[] tokenIds,
        uint256[] amounts,
        address pledger,
        uint256 price,
        uint256 interest,
        uint256 duration
    );

    ///@notice pledger cancel order
     // address[] lenders
    event PledgeCanceled(
        uint256 orderId,
        address pledger
    );

    ///@notice pledger taker order
    event PledgerDealed(
        uint256 orderId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest,
        uint256 duration,
        uint256 dealTime
    );

    ///@notice pledger repay debt
    event PledgerRepaid(
        uint256 orderId,
        address pledger,
        address lender,
        uint256 cost,
        uint256 devCommission
    );

    ///@notice lender lenderOffer
    event LenderOffered(
        uint256 orderId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest
    );

    ///@notice lender lenderCancelOffer
    event LenderOfferCanceled(
        uint256 orderId,
        address lender
    );

    ///@notice lender lenderDeal
    event LenderDealed(
        uint256 orderId,
        address lender,
        uint256 dealTime
    );

    ///@notice aution
    event Auctioned(
        uint256 orderId,
        address vendee,
        uint256 price,
        address previousVendee,
        uint256 previousPrice
    );

    ///@notice After the auction is completed, the winner will withdraw nft (if no one responds, the original lender will withdraw it)
    event Claimed(
        uint256 orderId,
        uint256 price,
        address taker
    );

    event SetRedemptionPeriod(uint256 _period);
    event SetClearingPeriod(uint256 _period);
    event SetRepayInterestCut(uint256 _cut);
    event SetAuctionCut(uint256 _pledgerCut, uint256 _devCut);

    event ProposeBeneficiary(address _pendingBeneficiary);
    event ClaimBeneficiary(address beneficiary);

    event SetMaxLendersCnt(
        address nftAddress,
        uint256 _maxLendersCnt
    );

    event SetDefaultMaxLendersCnt(uint256 _defaultMaxLendersCnt);

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "Beneficiary required");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == admin, "Admin required");
        _;
    }

    ///@notice initialize
    function initialize(
        address _usdxc,
        address _beneficiary,
        uint256 _redemptionPeriod,
        uint256 _clearingPeriod,
        uint256 _repayInterestCut,
        uint256 _auctionPledgerCut,
        uint256 _auctionDevCut
    ) external initializer {
        require(_usdxc != address(0), "_usdxc is zero address");
        require(_beneficiary != address(0), "_beneficiary is zero address");
        __ReentrancyGuard_init();
        admin = msg.sender;
        usdxc = _usdxc;
        beneficiary = _beneficiary;
        redemptionPeriod = _redemptionPeriod;
        clearingPeriod = _clearingPeriod;
        repayInterestCut = _repayInterestCut;
        auctionPledgerCut = _auctionPledgerCut;
        auctionDevCut = _auctionDevCut;
    }

    ///@notice nft pledger make order
    ///@param _nftAddress NFT address
    ///@param _tokenId tokenId
    ///@param _price price
    ///@param _interest interest
    ///@param _duration duration
    function pledge721(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _price,
        uint256 _interest,
        uint256 _duration
    ) external nonReentrant {
        require(_price > 0, "Invalid price");
        require(_interest > 0, "Invalid iinterest");
        require(_duration > 0, "Invalid duration");
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        
        _pledgeInternal(
            _nftAddress,
            tokenIds,
            amounts,
            _price,
            _interest,
            _duration,
            721
        );
    }

    function pledge721Bundle(
        address _nftAddress,
        uint256[] calldata _tokenIds,
        uint256 _price,
        uint256 _interest,
        uint256 _duration
    ) external nonReentrant {
        require(_tokenIds.length > 0, "no tokenId");
        require(_price > 0, "Invalid price");
        require(_interest > 0, "Invalid interest");
        require(_duration > 0, "Invalid duration");

        uint256[] memory amounts = new uint256[](_tokenIds.length);
        _pledgeInternal(
            _nftAddress,
            _tokenIds,
            amounts,
            _price,
            _interest,
            _duration,
            721
        );
    }

    function pledge1155(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _price,
        uint256 _interest,
        uint256 _duration
    ) external nonReentrant {
        require(_price > 0, "Invalid price");
        require(_interest > 0, "Invalid interest");
        require(_duration > 0, "Invalid duration");
        require(_amount > 0, "Invalid amount");
        

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = _amount;
        _pledgeInternal(
            _nftAddress,
            tokenIds,
            amounts,
            _price,
            _interest,
            _duration,
            1155
        );
    }

    function pledge1155Batch(
        address _nftAddress,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        uint256 _price,
        uint256 _interest,
        uint256 _duration
    ) external nonReentrant {
        require(_tokenIds.length > 0, "no tokenId");
        require(_amounts.length > 0, "invalid amount");
        require(
            _tokenIds.length == _amounts.length,
            "tokenIds length should equal amouts"
        );
        require(_price > 0, "Invalid price");
        require(_interest > 0, "Invalid iinterest");
        require(_duration > 0, "Invalid duration");

        _pledgeInternal(
            _nftAddress,
            _tokenIds,
            _amounts,
            _price,
            _interest,
            _duration,
            1155
        );
    }

    function _pledgeInternal(
        address _nftAddress,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        uint256 _price,
        uint256 _interest,
        uint256 _duration,
        uint256 _nftType
    ) internal {
        require(_nftType == 721 || _nftType == 1155, "don't support this nft type");
        require(_tokenIds.length > 0, "no tokenId");
        require(_amounts.length > 0, "invalid amount");
        require(
            _tokenIds.length == _amounts.length,
            "tokenIds length should equal amouts"
        );

        _transferNfts(
            msg.sender,
            address(this),
            _nftAddress,
            _tokenIds,
            _amounts,
            _nftType
        );

        OrderDetail storage detail = orders[counter];
        detail.nftAddress = _nftAddress;
        detail.pledger = msg.sender;
        detail.listOffer.price = _price;
        detail.listOffer.interest = _interest;

        detail.duration = _duration;

        detail.nftType = _nftType;
        detail.tokenIds = _tokenIds;
        detail.amounts = _amounts;

        detail.status = OrderStatus.LISTED;


        emit Pledged(
            counter,
            _nftAddress,
            _nftType,
            _tokenIds,
            _amounts,
            msg.sender,
            _price,
            _interest,
            _duration
        );

        counter += 1;
    }

    function _transferNfts(
        address _from,
        address _to,
        address _nftAddress,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        uint256 _nftType
    ) internal {
        require(_nftType == 721 || _nftType == 1155, "don't support this nft type");
        require(_tokenIds.length > 0, "no tokenId");
        require(_amounts.length > 0, "invalid amount");
        require(
            _tokenIds.length == _amounts.length,
            "tokenIds length should equal amouts"
        );

        if (_nftType == 721) {
            for (uint256 i = 0; i < _tokenIds.length; i++) {
                IERC721Upgradeable(_nftAddress).safeTransferFrom(
                    _from,
                    _to,
                    _tokenIds[i]
                );
            }
        } else if (_nftType == 1155) {
            if (_tokenIds.length == 1) {
                IERC1155Upgradeable(_nftAddress).safeTransferFrom(
                    _from,
                    _to,
                    _tokenIds[0],
                    _amounts[0],
                    ""
                );
            } else {
                IERC1155Upgradeable(_nftAddress).safeBatchTransferFrom(
                    _from,
                    _to,
                    _tokenIds,
                    _amounts,
                    ""
                );
            }
        }
    }

    ///@notice nft pledger cancle order
    function cancelPledge(uint256 _orderId)
        external
        nonReentrant
    {
        require(
            getNftStatus(_orderId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );

        OrderDetail storage detail = orders[_orderId];
        require(detail.pledger == msg.sender, "Auth failed");

        detail.status = OrderStatus.CANCELED;

        // address[] memory _lenders =
        //     new address[](detail.lendersAddress.length());

        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            // give back lenders their token
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            // _lenders[i] = _lender;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
        }

        _transferNfts(address(this), msg.sender, detail.nftAddress, detail.tokenIds, detail.amounts, detail.nftType);
        // emit PledgeCanceled(_orderId, msg.sender, _lenders);
        emit PledgeCanceled(_orderId, msg.sender);
    }

    ///@notice nft The pledger chooses a suitable lender and completes the order
    function pledgerDeal(
        uint256 _orderId,
        address _lender,
        uint256 _price,
        uint256 _interest
    ) external nonReentrant {
        require(
            getNftStatus(_orderId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        require(_price > 0, "invalid price");
        require(_interest > 0, "invalid interest");


        OrderDetail storage detail = orders[_orderId];
        require(detail.pledger == msg.sender, "Auth failed");
        require(detail.lendersAddress.contains(_lender), "Invalid lender");
        

        Offer memory _lenderDetail = detail.lenders[_lender];
        require(
            _price == _lenderDetail.price && _interest == _lenderDetail.interest,
            "Invalid price"
        );

        uint256 n = detail.lendersAddress.length();
        for (uint256 i = 0; i < n; ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address tmpLender = detail.lendersAddress.at(i);
            uint256 tmpLenderPrice = detail.lenders[tmpLender].price;
            if (_lender == tmpLender) {
                IERC20Upgradeable(usdxc).safeTransfer(msg.sender, tmpLenderPrice);
            } else {
                if (tmpLenderPrice > 0 ) {
                    IERC20Upgradeable(usdxc).safeTransfer(tmpLender, tmpLenderPrice);
                }
            }
        }

        detail.lender = _lender;
        detail.dealOffer.price = _lenderDetail.price;
        detail.dealOffer.interest = _lenderDetail.interest;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        IPubSubMgr(pubSubMgr).publish(
            keccak256("deposit"),
            abi.encode(
                _orderId,
                detail.nftAddress,
                detail.tokenIds,
                msg.sender,
                _lender,
                _price,
                detail.duration
            )
        );

        emit PledgerDealed(
            _orderId,
            msg.sender,
            _lender,
            detail.dealOffer.price,
            detail.dealOffer.interest,
            detail.duration,
            detail.dealTime
        );
    }

    ///@notice nft pledger repay debt
    function pledgerRepay(uint256 orderId)
        external
        nonReentrant
    {
        require(
            getNftStatus(orderId) == OrderStatus.MORTGAGED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        require(detail.pledger == msg.sender, "Auth failed");

        uint256 _price = detail.dealOffer.price;
        uint256 _cost = _price.add(detail.dealOffer.interest);
        uint256 _devCommission = detail.dealOffer.interest.mul(repayInterestCut).div(
            MAX_REPAY_INTEREST_CUT
        );
        address _lender = detail.lender;
        detail.status = OrderStatus.REPAID;

        _transferNfts(address(this), detail.pledger, detail.nftAddress, detail.tokenIds, detail.amounts, detail.nftType);
    
        
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            beneficiary,
            _devCommission
        );
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            _lender,
            _cost.sub(_devCommission)
        );

        IPubSubMgr(pubSubMgr).publish(
            keccak256("withdraw"),
            abi.encode(orderId, detail.nftAddress, msg.sender, _lender, _price)
        );

        emit PledgerRepaid(
            orderId,
            msg.sender,
            _lender,
            _cost,
            _devCommission
        );
    }

    ///@notice lender makes offer
    ///@param orderId orderId
    ///@param price price
    ///@param interest interest
    function lenderOffer(
        uint256 orderId,
        uint256 price,
        uint256 interest
    ) external nonReentrant {
        require(
            getNftStatus(orderId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        require(!detail.lendersAddress.contains(msg.sender), "Already offered");
        require(price > 0, "Invalid price");
        uint256 n = detail.lendersAddress.length();
        require(
            maxLendersCnt[detail.nftAddress] == 0 ||
                n < maxLendersCnt[detail.nftAddress],
            "exeed max lenders cnt"
        );
        require(
            defaultMaxLendersCnt == 0 || n < defaultMaxLendersCnt,
            "exceed default max lenders cnt"
        );

        detail.lendersAddress.add(msg.sender);
        detail.lenders[msg.sender] = Offer({
            price: price,
            interest: interest
        });
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            address(this),
            price
        );

        emit LenderOffered(
            orderId,
            detail.pledger,
            msg.sender,
            price,
            interest
        );
    }

    // lender cancle order
    function lenderCancelOffer(uint256 orderId)
        external
        nonReentrant
    {
        require(
            getNftStatus(orderId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        require(detail.lendersAddress.contains(msg.sender), "No offer");

        Offer memory _lenderOffer = detail.lenders[msg.sender];
        uint256 offerPrice = _lenderOffer.price;
        delete detail.lenders[msg.sender];
        
        detail.lendersAddress.remove(msg.sender);

        IERC20Upgradeable(usdxc).safeTransfer(msg.sender, offerPrice);

        emit LenderOfferCanceled(orderId, msg.sender);
    }

    // lender 成单
    function lenderDeal(
        uint256 orderId,
        uint256 price,
        uint256 interest
    ) external nonReentrant {
        require(
            getNftStatus(orderId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        require(
            price == detail.listOffer.price && interest == detail.listOffer.interest,
            "Invalid price"
        );

        uint256 n = detail.lendersAddress.length();
        for (uint256 i = 0; i < n; ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
        }

        detail.lender = msg.sender;
        detail.dealOffer = detail.listOffer;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            detail.pledger,
            price
        );

        IPubSubMgr(pubSubMgr).publish(
            keccak256("deposit"),
            abi.encode(
                orderId,
                detail.nftAddress,
                detail.tokenIds,
                detail.pledger,
                detail.lender,
                detail.dealOffer.price,
                detail.duration
            )
        );

        emit LenderDealed(orderId, msg.sender, block.timestamp);
    }

    ///@notice auction
    function auction(
        uint256 orderId,
        uint256 price
    ) external nonReentrant {
        require(
            getNftStatus(orderId) == OrderStatus.CLEARING,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        require(msg.sender != detail.pledger, "Cannot auction self");
        require(price > detail.dealOffer.price.add(detail.dealOffer.interest), "Invalid price");
        uint256 previousPrice = detail.vendee.price;
        require(price > previousPrice, "Price too low");

        address previousVendee = detail.vendee.vendee;

        detail.vendee.vendee = msg.sender;
        detail.vendee.price = price;

        if (previousVendee != address(0)) {
            IERC20Upgradeable(usdxc).safeTransfer(
                previousVendee,
                previousPrice
            );
        }
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            address(this),
            price
        );

        emit Auctioned(
            orderId,
            msg.sender,
            price,
            previousVendee,
            previousPrice
        );
    }

    ///@notice Distributed after the auction phase is over
    ///@param orderId orderId
    function claim(uint256 orderId) external nonReentrant {
        require(
            getNftStatus(orderId) == OrderStatus.CLAIMABLE,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[orderId];
        
        detail.status = OrderStatus.CLAIMED;

        address vendee = detail.vendee.vendee;
        address lender = detail.lender;
        if (vendee != address(0)) {
            // When there is an auctioneer, distribute the auctioneer’s token
            uint256 _price = detail.vendee.price;
            uint256 _profit = _price.sub(detail.dealOffer.price).sub(detail.dealOffer.interest);
            uint256 _beneficiaryCommissionOfInterest = detail
                .dealOffer.interest
                .mul(repayInterestCut)
                .div(MAX_REPAY_INTEREST_CUT);
            uint256 _beneficiaryCommissionOfProfit = _profit
                .mul(auctionDevCut)
                .div(MAX_REPAY_INTEREST_CUT);
            uint256 _beneficiaryCommission = _beneficiaryCommissionOfInterest
                .add(_beneficiaryCommissionOfProfit);
            uint256 _pledgerCommissionOfProfit = _profit
                .mul(auctionPledgerCut)
                .div(MAX_REPAY_INTEREST_CUT);

            IERC20Upgradeable(usdxc).safeTransfer(
                detail.pledger,
                _pledgerCommissionOfProfit
            );
            IERC20Upgradeable(usdxc).safeTransfer(
                beneficiary,
                _beneficiaryCommission
            );
            IERC20Upgradeable(usdxc).safeTransfer(
                lender,
                _price.sub(_beneficiaryCommission).sub(
                    _pledgerCommissionOfProfit
                )
            );
            _transferNfts(address(this), vendee, detail.nftAddress, detail.tokenIds, detail.amounts, detail.nftType);
            emit Claimed(orderId, _price, vendee);
        } else {
            // When there is no auctioneer, transfer nft
            _transferNfts(address(this), lender, detail.nftAddress, detail.tokenIds, detail.amounts, detail.nftType);
            emit Claimed(orderId, 0, lender);
        }

        IPubSubMgr(pubSubMgr).publish(
            keccak256("withdraw"),
            abi.encode(orderId, detail.nftAddress, detail.pledger, detail.lender, detail.dealOffer.price)
        );
       
    }

    ///@notice Get NFT status in the market
    function getNftStatus(uint256 _orderId)
        public
        view
        returns (OrderStatus)
    {
        OrderDetail storage detail = orders[_orderId];
        if (detail.pledger == address(0)) {
            return OrderStatus.NONEXIST;
        }

        if (detail.status == OrderStatus.MORTGAGED) {

            if (block.timestamp > detail.dealTime.add(detail.duration).add(redemptionPeriod).add(clearingPeriod)) {
                return OrderStatus.CLAIMABLE;
            }

            if (block.timestamp > detail.dealTime.add(detail.duration).add(redemptionPeriod)) {
                return OrderStatus.CLEARING;
            }
        }
        return detail.status;
    }

    function lenderOfferInfo(
        uint256 orderId,
        address user
    ) external view returns (uint256, uint256) {
        OrderDetail storage detail = orders[orderId];
        require(
            getNftStatus(orderId) != OrderStatus.NONEXIST,
            "order not exist"
        );
        // require(detail.lendersAddress.contains(user), "No offer");
        // detail.lendersAddress
        return (detail.lenders[user].price, detail.lenders[user].interest);
    }

    function t1(uint256 orderId)
        external
        view
        returns (uint256)
    {
        OrderDetail storage detail = orders[orderId];
        require(
            getNftStatus(orderId) != OrderStatus.NONEXIST,
            "order not exist"
        );

        return detail.lendersAddress.length();
    }

    function t2(
        uint256 orderId,
        uint256 index
    ) external view returns (address, uint256, uint256) {
        OrderDetail storage detail = orders[orderId];
        address lender =  detail.lendersAddress.at(index);
        return (lender, detail.lenders[lender].price, detail.lenders[lender].interest);
    }

    ///@notice set redemption period
    ///@param _period new redemption period
    function setRedemptionPeriod(uint256 _period) external onlyOwner {
        redemptionPeriod = _period;

        emit SetRedemptionPeriod(_period);
    }

    ///@notice set clearing period
    ///@param _period new clearing period
    function setClearingPeriod(uint256 _period) external onlyOwner {
        clearingPeriod = _period;

        emit SetClearingPeriod(_period);
    }

    ///@notice set repay interest cut
    ///@param _cut new repay interest cut
    function setRepayInterestCut(uint256 _cut) external onlyOwner {
        require(
            _cut <= MAX_REPAY_INTEREST_PLATFORM_CUT,
            "Invalid repay interest platform cut"
        );
        repayInterestCut = _cut;

        emit SetRepayInterestCut(_cut);
    }

    function setAuctionCut(uint256 _pledgerCut, uint256 _devCut)
        external
        onlyOwner
    {
        require(
            _pledgerCut.add(_devCut) < MAX_REPAY_INTEREST_CUT,
            "Invalid cut"
        );

        require(
            _pledgerCut <= MAX_AUCTION_PLEDGER_CUT,
            "Invalid auction pledger cut"
        );

        require(
            _devCut <= MAX_AUCTION_PLATFORM_CUT,
            "Invalid auction platform cut"
        );
        auctionPledgerCut = _pledgerCut;
        auctionDevCut = _devCut;

        emit SetAuctionCut(_pledgerCut, _devCut);
    }

    function proposeBeneficiary(address _pendingBeneficiary)
        external
        onlyBeneficiary
    {
        require(
            _pendingBeneficiary != address(0),
            "_pendingBeneficiary is zero address"
        );
        pendingBeneficiary = _pendingBeneficiary;

        emit ProposeBeneficiary(_pendingBeneficiary);
    }

    function claimBeneficiary() external {
        require(
            msg.sender == pendingBeneficiary,
            "msg.sender is not pendingBeneficiary"
        );
        beneficiary = pendingBeneficiary;
        pendingBeneficiary = address(0);

        emit ClaimBeneficiary(beneficiary);
    }

    ///@notice Set the maximum number of lenders
    ///@param _maxLendersCnt new maximum number of lenders
    function setMaxLendersCnt(
        address nftAddress,
        uint256 _maxLendersCnt
    ) external onlyOwner {
        maxLendersCnt[nftAddress] = _maxLendersCnt;
        emit SetMaxLendersCnt(nftAddress, _maxLendersCnt);
    }

    ///@notice Set the default maximum lenders amount
    ///@param _defaultMaxLendersCnt new default maximum lenders amount
    function setDefaultMaxLendersCnt(uint256 _defaultMaxLendersCnt)
        external
        onlyOwner
    {
        defaultMaxLendersCnt = _defaultMaxLendersCnt;
        emit SetDefaultMaxLendersCnt(_defaultMaxLendersCnt);
    }

    function setPubSubMgr(address _pubSubMgr) external onlyOwner {
        pubSubMgr = _pubSubMgr;
    }
    
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns(bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns(bytes4) {
        
        
        return this.onERC1155BatchReceived.selector;
    }
    
     function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return  interfaceId == 0x01ffc9a7 ||    // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
            interfaceId == 0x4e2312e0;     // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
    }

}
