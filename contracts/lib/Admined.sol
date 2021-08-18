// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract Admined is AccessControlUpgradeable {
    function __Admined_init(address admin) internal {
        __AccessControl_init();
        __Admined_init_unchained(admin);
    }

    function __Admined_init_unchained(address admin) internal {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
    }

    modifier onlyAdmin() {
        require(isAdmin(msg.sender), "Restricted to admins");
        _;
    }

    function isAdmin(address account) public view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    function getAdminCount() public view returns (uint256) {
        return getRoleMemberCount(DEFAULT_ADMIN_ROLE);
    }

    function addAdmin(address account) public virtual onlyAdmin {
        grantRole(DEFAULT_ADMIN_ROLE, account);
    }

    function renounceAdmin() public virtual {
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        require(
            getRoleMemberCount(DEFAULT_ADMIN_ROLE) >= 1,
            "At least one ADMIN"
        );
    }
}
