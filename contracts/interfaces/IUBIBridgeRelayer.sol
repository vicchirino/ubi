// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IUBIStreamNotifier {

    function addListener(address listenerAddress) virtual external;
    function removeListener(address listenerAddress) virtual external;
    function notifyStreamCreated(uint256 streamId, uint256 sender, uint256 recipient) virtual external;

}