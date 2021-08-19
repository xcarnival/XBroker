// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "./interface/IPubSubMgr.sol";

contract Broker is
    Initializable,
    IERC721ReceiverUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    enum OrderStatus {NONEXIST, LISTED, MORTGAGED, CLEARING, CLAIMABLE}

    ///@notice Lender detail
    ///@param price lender offer price
    ///@param interest lender offer interest
    struct LenderDetail {
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
        address lender;
        uint256 price;
        uint256 interest;
        uint256 duration;
        uint256 dealTime;
        OrderStatus status;
        VendeeDetail vendee;
        EnumerableSetUpgradeable.AddressSet lendersAddress;
        mapping(address => LenderDetail) lenders;
    }

    uint256 public constant MAX_REPAY_INTEREST_CUT = 1000;

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
    mapping(address => mapping(uint256 => OrderDetail)) orders;

    ///@notice To prevent malicious attacks, the maximum number of lenderAddresses for each NFT. After exceeding the maximum threshold, lenderOffer is not allowed, and 0 means no limit
    mapping(address => mapping(uint256 => uint256)) public maxLendersCnt;
    ///@notice The default value of the maximum number of lenderAddresses per NFT.
    uint256 public defaultMaxLendersCnt;

    address public pendingBeneficiary;

    uint256 public constant MAX_REPAY_INTEREST_PLATFORM_CUT = 200;

    uint256 public constant MAX_AUCTION_PLEDGER_CUT = 50;
    uint256 public constant MAX_AUCTION_PLATFORM_CUT = 200;

    // pubSubMgr contract
    address public pubSubMgr;

    ///@notice pledger maker order
    event Pledged(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        uint256 price,
        uint256 interest,
        uint256 duration
    );

    ///@notice pledger cancel order
    event PledgeCanceled(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address[] lenders
    );

    ///@notice pledger taker order
    event PledgerDealed(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest,
        uint256 duration,
        uint256 dealTime,
        address[] unsettledLenders
    );

    ///@notice pledger repay debt
    event PledgerRepaid(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 cost,
        uint256 devCommission
    );

    ///@notice lender lenderOffer
    event LenderOffered(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest
    );

    ///@notice lender lenderCancelOffer
    event LenderOfferCanceled(
        address nftAddress,
        uint256 tokenId,
        address lender
    );

    ///@notice lender lenderDeal
    event LenderDealed(
        address nftAddress,
        uint256 tokenId,
        address lender,
        uint256 dealTime
    );

    ///@notice aution
    event Auctioned(
        address nftAddress,
        uint256 tokenId,
        address vendee,
        uint256 price,
        address previousVendee,
        uint256 previousPrice
    );

    ///@notice After the auction is completed, the winner will withdraw nft (if no one responds, the original lender will withdraw it)
    event Claimed(
        address nftAddress,
        uint256 tokenId,
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
        uint256 tokenId,
        uint256 _maxLendersCnt
    );

    event SetDefaultMaxLendersCnt(
        uint256 _defaultMaxLendersCnt
    );

    modifier onlyBeneficiary {
        require(msg.sender == beneficiary, "Beneficiary required");
        _;
    }

    modifier onlyOwner {
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
    ///@param nftAddress NFT address
    ///@param tokenId tokenId
    ///@param price price
    ///@param interest interest
    ///@param duration duration
    function pledge(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 interest,
        uint256 duration
    ) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.NONEXIST,
            "Invalid NFT status"
        );
        require(price > 0, "Invalid price");

        OrderDetail storage detail = orders[nftAddress][tokenId];
        detail.pledger = msg.sender;
        detail.price = price;
        detail.interest = interest;
        detail.duration = duration;
        detail.status = OrderStatus.LISTED;

        IERC721Upgradeable(nftAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );
        emit Pledged(
            nftAddress,
            tokenId,
            msg.sender,
            price,
            interest,
            duration
        );
    }

    ///@notice nft pledger cancle order
    function cancelPledge(address nftAddress, uint256 tokenId)
        external
        nonReentrant
    {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");

        address[] memory _lenders =
            new address[](detail.lendersAddress.length());

        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            // give back lenders their token
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            _lenders[i] = _lender;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            // delete detail.lenders[_lender];
        }
        for (uint256 i = 0; i < _lenders.length; ++i) {
            detail.lendersAddress.remove(_lenders[i]);
            delete detail.lenders[_lenders[i]];
        }
        delete orders[nftAddress][tokenId];

        IERC721Upgradeable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
        emit PledgeCanceled(nftAddress, tokenId, msg.sender, _lenders);
    }

    ///@notice nft The pledger chooses a suitable lender and completes the order
    function pledgerDeal(
        address nftAddress,
        uint256 tokenId,
        address lender,
        uint256 price,
        uint256 interest
    ) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");
        require(detail.lendersAddress.contains(lender), "Invalid lender");

        LenderDetail memory _lenderDetail = detail.lenders[lender];
        require(
            price == _lenderDetail.price && interest == _lenderDetail.interest,
            "Invalid price"
        );
        address[] memory _unsettledLenders =
            new address[](detail.lendersAddress.length());
        uint256 _unsettledLendersCount = 0;

        uint256 n = detail.lendersAddress.length();
        for (uint256 i = 0; i < n; ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            if (_lender == lender) {
                IERC20Upgradeable(usdxc).safeTransfer(msg.sender, _lenderPrice);
            } else {
                _unsettledLenders[_unsettledLendersCount] = _lender;
                _unsettledLendersCount++;
                IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            }
            delete detail.lenders[_lender];
        }

        for (uint256 i = 0; i < n; ++i) {
            detail.lendersAddress.remove(detail.lendersAddress.at(0));
        }

        delete detail.lendersAddress;

        detail.lender = lender;
        detail.price = _lenderDetail.price;
        detail.interest = _lenderDetail.interest;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        IPubSubMgr(pubSubMgr).publish(keccak256("deposit"), abi.encode(nftAddress, tokenId, msg.sender, lender, price, detail.duration));

        emit PledgerDealed(
            nftAddress,
            tokenId,
            msg.sender,
            lender,
            detail.price,
            detail.interest,
            detail.duration,
            detail.dealTime,
            _unsettledLenders
        );
    }

    ///@notice nft pledger repay debt
    function pledgerRepay(address nftAddress, uint256 tokenId)
        external
        nonReentrant
    {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.MORTGAGED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");

        uint256 _price = detail.price;
        uint256 _cost = _price.add(detail.interest);
        uint256 _devCommission =
            detail.interest.mul(repayInterestCut).div(MAX_REPAY_INTEREST_CUT);
        address _lender = detail.lender;
        delete orders[nftAddress][tokenId];

        IERC721Upgradeable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
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

        IPubSubMgr(pubSubMgr).publish(keccak256("withdraw"), abi.encode(nftAddress, tokenId, msg.sender, _lender, _price));

        emit PledgerRepaid(
            nftAddress,
            tokenId,
            msg.sender,
            _lender,
            _cost,
            _devCommission
        );
    }

    ///@notice lender makes offer
    ///@param nftAddress nft address
    ///@param tokenId tokenId
    ///@param price price
    ///@param interest interest
    function lenderOffer(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 interest
    ) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(!detail.lendersAddress.contains(msg.sender), "Already offered");
        require(price > 0, "Invalid price");
        uint256 n = detail.lendersAddress.length();
        require(maxLendersCnt[nftAddress][tokenId] == 0 || n < maxLendersCnt[nftAddress][tokenId], "exeed max lenders cnt");
        require(defaultMaxLendersCnt == 0 || n < defaultMaxLendersCnt, "exceed default max lenders cnt");

        detail.lendersAddress.add(msg.sender);
        detail.lenders[msg.sender] = LenderDetail({
            price: price,
            interest: interest
        });
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            address(this),
            price
        );

        emit LenderOffered(
            nftAddress,
            tokenId,
            detail.pledger,
            msg.sender,
            price,
            interest
        );
    }

    // lender cancle order
    function lenderCancelOffer(address nftAddress, uint256 tokenId)
        external
        nonReentrant
    {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.lendersAddress.contains(msg.sender), "No offer");

        LenderDetail memory _lenderDetail = detail.lenders[msg.sender];
        delete detail.lenders[msg.sender];
        detail.lendersAddress.remove(msg.sender);
        IERC20Upgradeable(usdxc).safeTransfer(msg.sender, _lenderDetail.price);

        emit LenderOfferCanceled(nftAddress, tokenId, msg.sender);
    }

    // lender 成单
    function lenderDeal(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 interest
    ) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(
            price == detail.price && interest == detail.interest,
            "Invalid price"
        );

        uint256 n = detail.lendersAddress.length();
        for (uint256 i = 0; i < n; ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            delete detail.lenders[_lender];
        }

        for (uint i = 0; i < n; ++i) {
            detail.lendersAddress.remove(detail.lendersAddress.at(0));
        }

        delete detail.lendersAddress;

        detail.lender = msg.sender;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            detail.pledger,
            detail.price
        );

        IPubSubMgr(pubSubMgr).publish(keccak256("deposit"), abi.encode(nftAddress, tokenId, detail.pledger, msg.sender, price, detail.duration));
        emit LenderDealed(nftAddress, tokenId, msg.sender, block.timestamp);
    }

    ///@notice auction
    function auction(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.CLEARING,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(msg.sender != detail.pledger, "Cannot auction self");
        require(price > detail.price.add(detail.interest), "Invalid price");
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
            nftAddress,
            tokenId,
            msg.sender,
            price,
            previousVendee,
            previousPrice
        );
    }

    ///@notice Distributed after the auction phase is over
    ///@param nftAddress nft address
    ///@param tokenId token id
    function claim(address nftAddress, uint256 tokenId) external nonReentrant {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.CLAIMABLE,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        address vendee = detail.vendee.vendee;
        address lender = detail.lender;
        if (vendee != address(0)) {
            // When there is an auctioneer, distribute the auctioneer’s token
            uint256 _price = detail.vendee.price;
            uint256 _profit = _price.sub(detail.price).sub(detail.interest);
            uint256 _beneficiaryCommissionOfInterest =
                detail.interest.mul(repayInterestCut).div(
                    MAX_REPAY_INTEREST_CUT
                );
            uint256 _beneficiaryCommissionOfProfit =
                _profit.mul(auctionDevCut).div(MAX_REPAY_INTEREST_CUT);
            uint256 _beneficiaryCommission =
                _beneficiaryCommissionOfInterest.add(
                    _beneficiaryCommissionOfProfit
                );
            uint256 _pledgerCommissionOfProfit =
                _profit.mul(auctionPledgerCut).div(MAX_REPAY_INTEREST_CUT);

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
            IERC721Upgradeable(nftAddress).safeTransferFrom(
                address(this),
                vendee,
                tokenId
            );
            emit Claimed(nftAddress, tokenId, _price, vendee);
        } else {
            // When there is no auctioneer, transfer nft
            IERC721Upgradeable(nftAddress).safeTransferFrom(
                address(this),
                lender,
                tokenId
            );
            emit Claimed(nftAddress, tokenId, 0, lender);
        }
        IPubSubMgr(pubSubMgr).publish(keccak256("withdraw"), abi.encode(nftAddress, tokenId, detail.pledger, lender, detail.price));

        delete orders[nftAddress][tokenId];
    }

    ///@notice Get NFT status in the market
    function getNftStatus(address nftAddress, uint256 tokenId)
        public
        view
        returns (OrderStatus)
    {
        OrderDetail storage detail = orders[nftAddress][tokenId];
        if (detail.pledger == address(0)) {
            return OrderStatus.NONEXIST;
        }
        if (detail.lender == address(0)) {
            return OrderStatus.LISTED;
        }
        // todo Change the order to reduce gas?
        if (
            block.timestamp >
            detail.dealTime.add(detail.duration).add(redemptionPeriod).add(
                clearingPeriod
            )
        ) {
            return OrderStatus.CLAIMABLE;
        }
        if (
            block.timestamp >
            detail.dealTime.add(detail.duration).add(redemptionPeriod)
        ) {
            return OrderStatus.CLEARING;
        }
        return OrderStatus.MORTGAGED;
    }

    function lenderOfferInfo(
        address nftAddress,
        uint256 tokenId,
        address user
    ) external view returns (uint256, uint256) {
        OrderDetail storage detail = orders[nftAddress][tokenId];
        // detail.lendersAddress
        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            if (detail.lendersAddress.at(i) == user) {
                return (
                    detail.lenders[user].price,
                    detail.lenders[user].interest
                );
            }
        }
    }

    function t1(
        address nftAddress,
        uint256 tokenId
    ) external view returns (uint256) {
        OrderDetail storage detail = orders[nftAddress][tokenId];
        return detail.lendersAddress.length();
    }

    function t2(
        address nftAddress,
        uint256 tokenId,
        uint256 index
    ) external view returns (address) {
        OrderDetail storage detail = orders[nftAddress][tokenId];
        return detail.lendersAddress.at(index);
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
        require(_cut <= MAX_REPAY_INTEREST_PLATFORM_CUT, "Invalid repay interest platform cut");
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

    function proposeBeneficiary(address _pendingBeneficiary) external onlyBeneficiary {
        require(_pendingBeneficiary != address(0), "_pendingBeneficiary is zero address");
        pendingBeneficiary = _pendingBeneficiary;

        emit ProposeBeneficiary(_pendingBeneficiary);
    }


    function claimBeneficiary() external {
        require(msg.sender == pendingBeneficiary, "msg.sender is not pendingBeneficiary");
        beneficiary = pendingBeneficiary;
        pendingBeneficiary = address(0);

        emit ClaimBeneficiary(beneficiary);
    }

    ///@notice Set the maximum number of lenders
    ///@param _maxLendersCnt new maximum number of lenders
    function setMaxLendersCnt(address nftAddress, uint256 tokenId, uint256 _maxLendersCnt) external onlyOwner {
        maxLendersCnt[nftAddress][tokenId] = _maxLendersCnt;
        emit SetMaxLendersCnt(nftAddress, tokenId, _maxLendersCnt);
    }

    ///@notice Set the default maximum lenders amount
    ///@param _defaultMaxLendersCnt new default maximum lenders amount
    function setDefaultMaxLendersCnt(uint256 _defaultMaxLendersCnt) external onlyOwner {
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
}
