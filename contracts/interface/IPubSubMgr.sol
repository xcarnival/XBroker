// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

interface IPubSubMgr {
    function publish(bytes32 topic, bytes calldata data) external;
}
