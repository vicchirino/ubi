// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

struct Stream {
  address sender;
  address recipient;
  address tokenAddress;
  uint256 balance;
  Timeframe timeframe;
  Rate rate;
}

struct Timeframe {
  uint256 start;
  uint256 stop;
}

struct Rate {
  uint256 payment;
  uint256 interval;
}


/**
 * @dev Interface for EIP-1620 (https://eips.ethereum.org/EIPS/eip-1620);
 */
interface IEIP1620 {

  /// @dev triggered when create is successfully called.
  event LogCreate(uint256 indexed _streamId, address indexed _sender, address indexed _recipient, address _tokenAddress, uint256 _startBlock, uint256 _stopBlock, uint256 _payment, uint256 _interval);

  /// @dev Triggered when withdraw is successfully called.
  event LogWithdraw(uint256 indexed _streamId, address indexed _recipient, uint256 _funds);

  /// @dev Triggered when redeem is successfully called.
  // event LogRedeem(uint256 indexed _streamId, address indexed _sender, address indexed _recipient, uint256 _senderBalance, uint256 _recipientBalance);

  /// @dev Triggered when confirmUpdate is successfully called.
  // event LogConfirmUpdate(uint256 indexed _streamId, address indexed _confirmer, address _newTokenAddress, uint256 _newStopBlock, uint256 _newPayment, uint256 _newInterval);

  /// @dev Triggered when revokeUpdate is successfully called.
  // event LogRevokeUpdate(uint256 indexed _streamId, address indexed revoker, address _newTokenAddress, uint256 _newStopBlock, uint256 _newPayment, uint256 _newInterval);

  /// @dev Triggered when an update is approved by all involved parties.
  // event LogExecuteUpdate(uint256 indexed _newStreamId, address indexed _sender, address indexed _recipient, address _newTokenAddress, uint256 _newStopBlock, uint256 _newPayment, uint256 _newInterval);

  /// @dev Returns available funds for the given stream id and address.
  function balanceOf(uint256 _streamId, address _addr) external view returns(uint256);

  /// @dev Returns the full stream data, if the id points to a valid stream.
  function getStream(uint256 _streamId) external view returns (address sender, address recipient, address tokenAddress, uint256 balance, uint256 startBlock, uint256 stopBlock, uint256 payment, uint256 interval);

  /** 
    * @dev Creates a new stream between msg.sender and _recipient.
    * MUST allow senders to create multiple streams in parallel. SHOULD not accept Ether and only use ERC20-compatible tokens.
    * Triggers Event: LogCreate
    */
  function create(address _recipient, address _tokenAddress, uint256 _startBlock, uint256 _stopBlock, uint256 _payment, uint256 _interval) external;

  /**
    * @dev Withdraws all or a fraction of the available funds.
    * MUST allow only the recipient to perform this action.
    * Triggers Event: LogWithdraw
  */
  function withdraw(uint256 _streamId, uint256 _funds) external;

  /**
  * @dev
  * Redeems the stream by distributing the funds to the sender and the recipient.
  * SHOULD allow any party to redeem the stream.
  * Triggers Event: LogRedeem
  */
  //function redeem(uint256 _streamId) external;

  /**
  * @dev Signals one party’s willingness to update the stream
  * SHOULD allow any party to do this but MUST NOT be executed without consent from all involved parties.
  * Triggers Event: LogConfirmUpdate
  * Triggers Event: LogExecuteUpdate when the last involved party calls this function
  */
  //function update(uint256 _streamId, address _tokenAddress, uint256 _stopBlock, uint256 _payment, uint256 _interval) external;

  /**
  * @dev Revokes an update proposed by one of the involved parties.
  * MUST allow any party to do this.
  * Triggers Event: LogRevokeUpdate
  */
  //function confirmUpdate(uint256 _streamId, address _tokenAddress, uint256 _stopBlock, uint256 _payment, uint256 _interval) external;
}