// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

contract Broker is Initializable, IERC721ReceiverUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    enum OrderStatus {NONEXIST, LISTED, MORTGAGED, CLEARING, CLAIMABLE}

    ///@notice 出借人详情
    ///@param price lender offer price
    ///@param interest lender offer interest
    struct LenderDetail {
        uint256 price;
        uint256 interest;
    }

    ///@notice 拍卖买家详情
    ///@param vendee vendee address
    ///@param price vendee offer price
    struct VendeeDetail {
        address vendee;
        uint256 price;
    }

    ///@notice 订单详情
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

    ///@notice 管理员
    address public admin;

    ///@notice 平台收益地址
    address public beneficiary;

    ///@notice 赎回时间窗口
    uint256 public redemptionPeriod;

    ///@notice 清算时间窗口
    uint256 public clearingPeriod;

    ///@notice 利息平台抽成（base 1000）
    uint256 public repayInterestCut;

    ///@notice 拍卖利益，抵押人分成
    uint256 public autionPledgerCut;

    ///@notice 拍卖利益，平台分成
    uint256 public autionDevCut;

    ///@dev 订单详情列表
    mapping(address => mapping(uint256 => OrderDetail)) orders;

    ///@notice pledger 挂单
    event Pledged(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        uint256 price,
        uint256 interest,
        uint256 duration
    );

    ///@notice pledger 取消挂单
    event PledgeCanceled(address nftAddress, uint256 tokenId, address pledger);

    ///@notice pledger 成单
    event PledgerDealed(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest,
        uint256 duration,
        uint256 dealTime
    );

    ///@notice pledger 赎回
    event PledgerRepaid(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 cost
    );

    ///@notice lender 出价
    event LenderOffered(
        address nftAddress,
        uint256 tokenId,
        address pledger,
        address lender,
        uint256 price,
        uint256 interest
    );

    ///@notice lender 取消出价
    event LenderOfferCanceled(
        address nftAddress,
        uint256 tokenId,
        address lender
    );

    ///@notice lender 成单
    event LenderDealed(address nftAddress, uint256 tokenId, address lender);

    ///@notice 拍卖
    event Autioned(
        address nftAddress,
        uint256 tokenId,
        address vendee,
        uint256 price
    );

    ///@notice 拍卖完成拍得者提取nft（若无人应拍，最初出借人提取）
    event Claimed(
        address nftAddress,
        uint256 tokenId,
        uint256 price,
        address taker
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
        uint256 _autionPledgerCut,
        uint256 _autionDevCut
    ) public initializer {
        admin = msg.sender;
        usdxc = _usdxc;
        beneficiary = _beneficiary;
        redemptionPeriod = _redemptionPeriod;
        clearingPeriod = _clearingPeriod;
        repayInterestCut = _repayInterestCut;
        autionPledgerCut = _autionPledgerCut;
        autionDevCut = _autionDevCut;
    }

    // todo reentrancy
    ///@notice nft 抵押人挂单
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
    ) public {
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

    ///@notice nft 抵押人取消订单
    function cancelPledge(address nftAddress, uint256 tokenId) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");

        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            // give back lenders their token
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            delete detail.lenders[_lender];
        }
        delete orders[nftAddress][tokenId];

        IERC721Upgradeable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
        emit PledgeCanceled(nftAddress, tokenId, msg.sender);
    }

    ///@notice nft 抵押人选择合适 lender 后达成订单
    function pledgerDeal(
        address nftAddress,
        uint256 tokenId,
        address lender
    ) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");
        require(detail.lendersAddress.contains(lender), "Invalid lender");

        LenderDetail memory _lenderDetail = detail.lenders[lender];

        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            if (_lender == lender) {
                IERC20Upgradeable(usdxc).safeTransfer(msg.sender, _lenderPrice);
            } else {
                IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            }
            delete detail.lenders[_lender];
        }
        delete detail.lendersAddress;

        detail.lender = lender;
        detail.price = _lenderDetail.price;
        detail.interest = _lenderDetail.interest;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        emit PledgerDealed(
            nftAddress,
            tokenId,
            msg.sender,
            lender,
            detail.price,
            detail.interest,
            detail.duration,
            detail.dealTime
        );
    }

    ///@notice nft 抵押人赎回
    function pledgerRepay(address nftAddress, uint256 tokenId) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.MORTGAGED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.pledger == msg.sender, "Auth failed");

        uint256 _cost = detail.price.add(detail.interest);
        uint256 _commission =
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
            _commission
        );
        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            _lender,
            _cost.sub(_commission)
        );

        emit PledgerRepaid(nftAddress, tokenId, msg.sender, _lender, _cost);
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
    ) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        // todo require price > 0
        require(!detail.lendersAddress.contains(msg.sender), "Already offered");
        require(price > 0, "Invalid price");

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

    // lender 撤单
    function lenderCancelOffer(address nftAddress, uint256 tokenId) public {
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
    function lenderDeal(address nftAddress, uint256 tokenId) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.LISTED,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(detail.lendersAddress.contains(msg.sender), "No offer");

        for (uint256 i = 0; i < detail.lendersAddress.length(); ++i) {
            // transfer token of picked lender to pledger
            // transfer others' back
            address _lender = detail.lendersAddress.at(i);
            uint256 _lenderPrice = detail.lenders[_lender].price;
            IERC20Upgradeable(usdxc).safeTransfer(_lender, _lenderPrice);
            delete detail.lenders[_lender];
        }
        delete detail.lendersAddress;

        detail.lender = msg.sender;
        detail.dealTime = block.timestamp;
        detail.status = OrderStatus.MORTGAGED;

        IERC20Upgradeable(usdxc).safeTransferFrom(
            msg.sender,
            address(this),
            detail.price
        );

        emit LenderDealed(nftAddress, tokenId, msg.sender);
    }

    ///@notice 拍卖
    function auction(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    ) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.CLEARING,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        require(msg.sender != detail.pledger, "Cannot auction self");
        require(price > detail.price.add(detail.interest), "Invalid price");
        uint256 previousPrice = detail.vendee.price;
        require(price > previousPrice, "Price too low");

        detail.vendee.vendee = msg.sender;
        detail.vendee.price = price;

        address previousVendee = detail.vendee.vendee;

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

        emit Autioned(nftAddress, tokenId, msg.sender, price);
    }

    ///@notice 出借人或拍卖买家提取 nft
    function claim(address nftAddress, uint256 tokenId) public {
        require(
            getNftStatus(nftAddress, tokenId) == OrderStatus.CLAIMABLE,
            "Invalid NFT status"
        );
        OrderDetail storage detail = orders[nftAddress][tokenId];
        address vendee = detail.vendee.vendee;
        if (vendee != address(0)) {
            require(msg.sender == vendee, "Not vendee");
            uint256 _price = detail.vendee.price;
            uint256 profit = _price.sub(detail.price).sub(detail.interest);
            uint256 _beneficiaryCommissionOfInterest =
                detail.interest.mul(repayInterestCut).div(
                    MAX_REPAY_INTEREST_CUT
                );
            uint256 _beneficiaryCommissionOfProfit =
                profit.mul(autionDevCut).div(MAX_REPAY_INTEREST_CUT);
            uint256 _beneficiaryCommission =
                _beneficiaryCommissionOfInterest.add(
                    _beneficiaryCommissionOfProfit
                );
            uint256 _pledgerCommissionOfProfit =
                profit.mul(autionPledgerCut).div(MAX_REPAY_INTEREST_CUT);

            IERC20Upgradeable(usdxc).safeTransfer(
                detail.pledger,
                _pledgerCommissionOfProfit
            );
            IERC20Upgradeable(usdxc).safeTransfer(
                beneficiary,
                _beneficiaryCommission
            );
            IERC20Upgradeable(usdxc).safeTransfer(
                detail.lender,
                _price.sub(_beneficiaryCommission).sub(
                    _pledgerCommissionOfProfit
                )
            );
            emit Claimed(nftAddress, tokenId, _price, msg.sender);
        } else {
            require(msg.sender == detail.lender, "Not lender");
            emit Claimed(nftAddress, tokenId, 0, msg.sender);
        }

        IERC721Upgradeable(nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
    }

    ///@notice 获取市场中的 NFT 状态
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
        // todo 改变顺序降低 gas？
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

    ///@notice 设置赎回时间窗口
    ///@param _period 新时间窗口
    function setRedemptionPeriod(uint256 _period) public onlyOwner {
        redemptionPeriod = _period;
    }

    ///@notice 设置清算时间窗口
    ///@param _period 新时间窗口
    function setClearingPeriod(uint256 _period) public onlyOwner {
        clearingPeriod = _period;
    }

    ///@notice 设置平台抽成
    ///@param _cut 新平台抽成
    function setRepayInterestCut(uint256 _cut) public onlyOwner {
        require(_cut < MAX_REPAY_INTEREST_CUT, "Invalid cut");
        repayInterestCut = _cut;
    }

    function setAutionCut(uint256 _pledgerCut, uint256 _devCut)
        public
        onlyOwner
    {
        require(
            _pledgerCut.add(_devCut) < MAX_REPAY_INTEREST_CUT,
            "Invalid cut"
        );
        autionPledgerCut = _pledgerCut;
        autionDevCut = _devCut;
    }

    function setBeneficiary(address _beneficiary) public onlyBeneficiary {
        beneficiary = _beneficiary;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {}
}