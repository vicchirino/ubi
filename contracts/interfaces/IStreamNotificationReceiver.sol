// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IUBIStreamNotificationReceiver {
    function onStreamNotification(uint256 streamId, uint256 sender) virtual external;
}