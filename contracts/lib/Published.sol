// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./Owned.sol";

contract Published is Owned {
    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");

    event AddedPublisher(address indexed account);
    event RemovedPublisher(address indexed account);

    function __Published_init(address admin, address owner, address publisher) internal {
        __Owned_init(admin, owner);
        __Published_init_unchained(publisher);
    }

    function __Published_init_unchained(address publisher) internal {
        _setRoleAdmin(PUBLISHER_ROLE, OWNER_ROLE);
        _setupRole(PUBLISHER_ROLE, publisher);
    }

    modifier onlyPublisher() {
        require(isPublisher(msg.sender), "!publisher");
        _;
    }

    function isPublisher(address account) public view returns (bool) {
        return hasRole(PUBLISHER_ROLE, account);
    }

    function getPublisher() public view returns (address[] memory) {
        uint256 count = getRoleMemberCount(PUBLISHER_ROLE);
        address[] memory whiteList = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            whiteList[i] = getRoleMember(PUBLISHER_ROLE, i);
        }
        return whiteList;
    }

    function addPublisher(address account) public onlyOwner {
        grantRole(PUBLISHER_ROLE, account);
        emit AddedPublisher(account);
    }

    function removePublisher(address account) public onlyOwner {
        revokeRole(PUBLISHER_ROLE, account);
        emit RemovedPublisher(account);
    }
}
