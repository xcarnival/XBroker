// SPDX-License-Identifier: MIT
// pragma solidity 0.6.12;
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Owned.sol";

contract Paused is PausableUpgradeable, Owned {
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    event AddedPauser(address indexed account);
    event RemovedPauser(address indexed account);

    function __Paused_init(
        address admin,
        address owner,
        address pauser
    ) internal {
        __Owned_init(admin, owner);
        __Paused_init_unchained(pauser);
    }

    function __Paused_init_unchained(address pauser) internal {
        __Pausable_init_unchained();
        _setRoleAdmin(PAUSE_ROLE, OWNER_ROLE);
        _setupRole(PAUSE_ROLE, pauser);
    }

    modifier onlyPauser() {
        require(isPauser(msg.sender), "!PAUSE_ROLE");
        _;
    }

    function isPauser(address account) public view returns (bool) {
        return hasRole(PAUSE_ROLE, account);
    }

    function getPausers() public view returns (address[] memory) {
        uint256 count = getRoleMemberCount(PAUSE_ROLE);
        address[] memory accounts = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            accounts[i] = getRoleMember(PAUSE_ROLE, i);
        }
        return accounts;
    }

    function addPauser(address account) public onlyOwner {
        grantRole(PAUSE_ROLE, account);
        emit AddedPauser(account);
    }

    function removePauser(address account) public onlyOwner {
        revokeRole(PAUSE_ROLE, account);
        emit RemovedPauser(account);
    }

    function pause() public onlyPauser {
        super._pause();
    }

    function unpause() public onlyPauser {
        super._unpause();
    }
}
