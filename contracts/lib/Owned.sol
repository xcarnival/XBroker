// SPDX-License-Identifier: MIT
// pragma solidity 0.6.12;
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./Admined.sol";

contract Owned is Admined {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    event AddedOwner(address indexed account);
    event RemovedOwner(address indexed account);
    event RenouncedOwner(address indexed account);

    function __Owned_init(address admin, address owner) internal {
        __Admined_init(admin);
        __Owned_init_unchained(owner);
    }

    function __Owned_init_unchained(address owner) internal {
        _setRoleAdmin(OWNER_ROLE, DEFAULT_ADMIN_ROLE);
        _setupRole(OWNER_ROLE, owner);
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!owner");
        _;
    }

    function isOwner(address account) public view returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }

    function getOwners() public view returns (address[] memory) {
        uint256 count = getRoleMemberCount(OWNER_ROLE);
        address[] memory owners = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            owners[i] = getRoleMember(OWNER_ROLE, i);
        }
        return owners;
    }

    function addOwner(address account) public onlyAdmin {
        grantRole(OWNER_ROLE, account);
        emit AddedOwner(account);
    }

    function removeOwner(address account) public onlyAdmin {
        revokeRole(OWNER_ROLE, account);
        emit RemovedOwner(account);
    }

    function renounceOwner() public {
        renounceRole(OWNER_ROLE, msg.sender);
        emit RenouncedOwner(msg.sender);
    }

    uint256[50] private __gap;
}
