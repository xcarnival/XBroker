// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./Owned.sol";

abstract contract Blacklist is Owned {
    bytes32 public constant BLACKLISTED_ROLE = keccak256("BLACKLISTED_ROLE");

    function __Blacklist_init(address admin, address owner) internal {
        __Owned_init(admin, owner);
        __Blacklist_init_unchained();
    }

    function __Blacklist_init_unchained() internal {
        _setRoleAdmin(BLACKLISTED_ROLE, OWNER_ROLE);
    }

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);

    modifier notBlacklisted(address account) {
        require(!isBlacklisted(account), "account-is-blacklisted");
        _;
    }

    function isBlacklisted(address account) public view returns (bool) {
        return hasRole(BLACKLISTED_ROLE, account);
    }

    function blacklist(address account) external onlyOwner {
        grantRole(BLACKLISTED_ROLE, account);
        emit Blacklisted(account);
    }

    function unblacklist(address account) external onlyOwner {
        revokeRole(BLACKLISTED_ROLE, account);
        emit UnBlacklisted(account);
    }

    uint256[50] private __gap;
}
