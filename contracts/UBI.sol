// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

/**
 * This code contains elements of ERC20BurnableUpgradeable.sol https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/master/contracts/token/ERC20/ERC20BurnableUpgradeable.sol
 * Those have been inlined for the purpose of gas optimization.
 */

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IEIP1620.sol";
import "hardhat/console.sol";

/**
 * @title ProofOfHumanity Interface
 * @dev See https://github.com/Proof-Of-Humanity/Proof-Of-Humanity.
 */
interface IProofOfHumanity {
  function isRegistered(address _submissionID)
    external
    view
    returns (
      bool registered
    );
}


/**
 * @title Poster Interface
 * @dev See https://github.com/auryn-macmillan/poster
 */
interface IPoster {
  event NewPost(bytes32 id, address user, string content);

  function post(string memory content) external;
}

/**
 * @title Universal Basic Income
 * @dev UBI is an ERC20 compatible token that is connected to a Proof of Humanity registry.
 *
 * Tokens are issued and drip over time for every verified submission on a Proof of Humanity registry.
 * The accrued tokens are updated directly on every wallet using the `balanceOf` function.
 * The tokens get effectively minted and persisted in memory when someone interacts with the contract doing a `transfer` or `burn`.
 */
contract UBI is Initializable, IEIP1620 {

  /* Events */

  /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
   *
   * Note that `value` may be zero.
   * Also note that due to continuous minting we cannot emit transfer events from the address 0 when tokens are created.
   * In order to keep consistency, we decided not to emit those events from the address 0 even when minting is done within a transaction.
   */
  event Transfer(address indexed from, address indexed to, uint256 value);

  /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /**
   * @dev Emitted when the `delegator` delegates its UBI accruing to the `delegate` by
   * a call to {delegate}.
   */
  event DelegateChange(address indexed delegator, address indexed delegate);

  using SafeMath for uint256;

  /* Storage */

  mapping (address => uint256) private balance;

  mapping (address => mapping (address => uint256)) public allowance;

  /// @dev A lower bound of the total supply. Does not take into account tokens minted as UBI by an address before it moves those (transfer or burn).
  uint256 public totalSupply;

  /// @dev Name of the token.
  string public name;

  /// @dev Symbol of the token.
  string public symbol;

  /// @dev Number of decimals of the token.
  uint8 public decimals;

  /// @dev How many tokens per second will be minted for every valid human.
  uint256 public accruedPerSecond;

  /// @dev The contract's governor.
  address public governor;

  /// @dev The Proof Of Humanity registry to reference.
  IProofOfHumanity public proofOfHumanity;

  /// @dev Timestamp since human started accruing.
  mapping(address => uint256) public accruedSince;

  /// @dev The approved addresses to delegate UBI to.
  mapping(address => address) public delegateOf;

  /// @dev The inverse of `delegateOf`.
  mapping(address => address) public inverseDelegateOf;
  
  /// @dev The UBI accruing factor.
  mapping(address => uint256) public accruingFactor;

  /* Modifiers */

  /// @dev Verifies that the sender has ability to modify governed parameters.
  modifier onlyByGovernor() {
    require(governor == msg.sender, "The caller is not the governor.");
    _;
  }

  /* Initializer */

  /** @dev Constructor.
  *  @param _initialSupply for the UBI coin including all decimals.
  *  @param _name for UBI coin.
  *  @param _symbol for UBI coin ticker.
  *  @param _accruedPerSecond How much of the token is accrued per block.
  *  @param _proofOfHumanity The Proof Of Humanity registry to reference.
  */
  function initialize(uint256 _initialSupply, string memory _name, string memory _symbol, uint256 _accruedPerSecond, IProofOfHumanity _proofOfHumanity) public initializer {
    name = _name;
    symbol = _symbol;
    decimals = 18;

    accruedPerSecond = _accruedPerSecond;
    proofOfHumanity = _proofOfHumanity;
    governor = msg.sender;

    balance[msg.sender] = _initialSupply;
    totalSupply = _initialSupply;
  }

  /* External */

  /** @dev Starts accruing UBI for a registered submission.
  *  @param _human The submission ID.
  */
  function startAccruing(address _human) external {
    require(proofOfHumanity.isRegistered(_human), "The submission is not registered in Proof Of Humanity.");
    require(accruedSince[_human] == 0, "The submission is already accruing UBI.");
    accruedSince[_human] = block.timestamp;
    accruingFactor[_human] = 1;
  }

  /** @dev Allows anyone to report a submission that
  *  should no longer receive UBI due to removal from the
  *  Proof Of Humanity registry. The reporter receives any
  *  leftover accrued UBI.
  *  @param _human The submission ID.
  */
  function reportRemoval(address _human) external  {
    require(!proofOfHumanity.isRegistered(_human), "The submission is still registered in Proof Of Humanity.");
    require(accruedSince[_human] != 0 && delegateOf[_human] == address(0), "The submission is not accruing UBI.");

    // If the submission is delegated, calculate the supply from the delegate and remove its accruing factor
    uint256 newSupply;
    if(delegateOf[_human] != address(0)) {
      address delegate = delegateOf[_human];
      newSupply = accruedPerSecond.mul(block.timestamp.sub(accruedSince[delegate])).mul(this.getAccruingFactor(delegate));
      accruingFactor[delegate] = this.getAccruingFactor(delegate).sub(1);
    }

    accruedSince[_human] = 0;
    accruingFactor[_human] = 0;

    balance[msg.sender] = balance[msg.sender].add(newSupply);
    totalSupply = totalSupply.add(newSupply);
  }

  /** @dev Changes `governor` to `_governor`.
  *  @param _governor The address of the new governor.
  */
  function changeGovernor(address _governor) external onlyByGovernor {
    governor = _governor;
  }

  /** @dev Changes `proofOfHumanity` to `_proofOfHumanity`.
  *  @param _proofOfHumanity Registry that meets interface of Proof of Humanity.
  */
  function changeProofOfHumanity(IProofOfHumanity _proofOfHumanity) external onlyByGovernor {
    proofOfHumanity = _proofOfHumanity;
  }

  /** @dev Transfers `_amount` to `_recipient` and withdraws accrued tokens.
  *  @param _recipient The entity receiving the funds.
  *  @param _amount The amount to tranfer in base units.
  */
  function transfer(address _recipient, uint256 _amount) public returns (bool) {
    uint256 newSupplyFrom;
    if (accruedSince[msg.sender] != 0) {
        newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[msg.sender])).mul(this.getAccruingFactor(msg.sender));
        totalSupply = totalSupply.add(newSupplyFrom);
        accruedSince[msg.sender] = block.timestamp;
    }
    balance[msg.sender] = balance[msg.sender].add(newSupplyFrom).sub(_amount, "ERC20: transfer amount exceeds balance");
    balance[_recipient] = balance[_recipient].add(_amount);
    emit Transfer(msg.sender, _recipient, _amount);
    return true;
  }

  /** @dev Transfers `_amount` from `_sender` to `_recipient` and withdraws accrued tokens.
  *  @param _sender The entity to take the funds from.
  *  @param _recipient The entity receiving the funds.
  *  @param _amount The amount to tranfer in base units.
  */
  function transferFrom(address _sender, address _recipient, uint256 _amount) public returns (bool) {
    uint256 newSupplyFrom;
    allowance[_sender][msg.sender] = allowance[_sender][msg.sender].sub(_amount, "ERC20: transfer amount exceeds allowance");
    if (accruedSince[_sender] != 0 && accruingFactor[_sender] != 0) {
        newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[_sender])).mul(this.getAccruingFactor(_sender));
        totalSupply = totalSupply.add(newSupplyFrom);
        accruedSince[_sender] = block.timestamp;
    }
    balance[_sender] = balance[_sender].add(newSupplyFrom).sub(_amount, "ERC20: transfer amount exceeds balance");
    balance[_recipient] = balance[_recipient].add(_amount);
    emit Transfer(_sender, _recipient, _amount);
    return true;
  }

  /** @dev Approves `_spender` to spend `_amount`.
  *  @param _spender The entity allowed to spend funds.
  *  @param _amount The amount of base units the entity will be allowed to spend.
  */
  function approve(address _spender, uint256 _amount) public returns (bool) {
    allowance[msg.sender][_spender] = _amount;
    emit Approval(msg.sender, _spender, _amount);
    return true;
  }

  /** @dev Increases the `_spender` allowance by `_addedValue`.
  *  @param _spender The entity allowed to spend funds.
  *  @param _addedValue The amount of extra base units the entity will be allowed to spend.
  */
  function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
    uint256 newAllowance = allowance[msg.sender][_spender].add(_addedValue);
    allowance[msg.sender][_spender] = newAllowance;
    emit Approval(msg.sender, _spender, newAllowance);
    return true;
  }

  /** @dev Decreases the `_spender` allowance by `_subtractedValue`.
  *  @param _spender The entity whose spending allocation will be reduced.
  *  @param _subtractedValue The reduction of spending allocation in base units.
  */
  function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
    uint256 newAllowance = allowance[msg.sender][_spender].sub(_subtractedValue, "ERC20: decreased allowance below zero");
    allowance[msg.sender][_spender] = newAllowance;
    emit Approval(msg.sender, _spender, newAllowance);
    return true;
  }

  /** @dev Burns `_amount` of tokens and withdraws accrued tokens.
  *  @param _amount The quantity of tokens to burn in base units.
  */
  function burn(uint256 _amount) public {
    uint256 newSupplyFrom;
    if(accruedSince[msg.sender] != 0) {
      newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[msg.sender]));
      accruedSince[msg.sender] = block.timestamp;
    }
    balance[msg.sender] = balance[msg.sender].add(newSupplyFrom).sub(_amount, "ERC20: burn amount exceeds balance");    
    totalSupply = totalSupply.add(newSupplyFrom).sub(_amount);
    emit Transfer(msg.sender, address(0), _amount);
  }

  /** @dev Burns `_amount` of tokens and posts content in a Poser contract.
  *  @param _amount The quantity of tokens to burn in base units.
  *  @param _poster the address of the poster contract.
  *  @param content bit of strings to signal.
  */
  function burnAndPost(uint256 _amount, address _poster, string memory content) public {
    burn(_amount);
    IPoster poster = IPoster(_poster);
    poster.post(content);
  }

  /** @dev Calculate the new supply corresponding to  the given account from the accrued value.
  */
  function getNewSupplyFrom(address _account) public view returns(uint256){
    uint256 newSupplyFrom = getAccruedValue(_account);
    return newSupplyFrom;
  }

  /** @dev Burns `_amount` of tokens from `_account` and withdraws accrued tokens.
  *  @param _account The entity to burn tokens from.
  *  @param _amount The quantity of tokens to burn in base units.
  */
  function burnFrom(address _account, uint256 _amount) public {
    uint256 newSupplyFrom;
    allowance[_account][msg.sender] = allowance[_account][msg.sender].sub(_amount, "ERC20: burn amount exceeds allowance");
    if (accruedSince[_account] != 0) {
        newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[_account]));
        accruedSince[_account] = block.timestamp;
    }
    balance[_account] = balance[_account].add(newSupplyFrom).sub(_amount, "ERC20: burn amount exceeds balance");
    totalSupply = totalSupply.add(newSupplyFrom).sub(_amount);
    emit Transfer(_account, address(0), _amount);
  }

  /* Getters */

  /** @dev Calculates how much UBI a submission has available for withdrawal.
  *  @param _account The submission ID.
  *  @return accrued The available UBI for withdrawal.
  */
  function getAccruedValue(address _account) public view returns (uint256 accrued) {
    // If this human have not started to accrue, or is not registered, return 0.
    if (accruedSince[_account] == 0 || accruingFactor[_account] == 0) return 0;

    // If account is not a registered human, and the delegator is not registered, return 0;
    if(!proofOfHumanity.isRegistered(_account) && !proofOfHumanity.isRegistered(inverseDelegateOf[_account])) return 0;

    return accruedPerSecond.mul(block.timestamp.sub(accruedSince[_account])).mul(this.getAccruingFactor(_account));
  }

  /**
  * @dev Calculates the current account balance, considering the accrued value if it's a human.
  * @param _account The account for which to calculate the balance.
  * @return The current balance including accrued Universal Basic Income of the user.
  **/
  function balanceOf(address _account) public view returns (uint256) {

  uint256 realAccruedValue = getAccruedValue(_account);

  // Subtract the delegated accrued value
  uint streamsLen = delegations[_account];
  for(uint256 i = 0; i <  streamsLen; i++) {
    realAccruedValue = realAccruedValue.sub(getStreamAccruedValue(delegations[_account][i]));
  }

    realAccruedValue.add(balance[_account]);
  }

  /** @dev Accruing factor resolves how much UBI a single account can accrue per timeframe */
  function getAccruingFactor(address _account) public view returns(uint256) {
    
    // If it's not delegated and there is no accruing factor, then it's not initialized. This solves for already registered humans.
    bool accruingFactorNotInitialized = delegateOf[_account] == address(0) && accruingFactor[_account] == 0;
    
    // If accruing factor is not initialized and it's a registered human, hardcode the initial accruing factor to be 1.
    uint256 initialization = accruingFactorNotInitialized && proofOfHumanity.isRegistered(_account) ? 1 : 0;

    // Humans should have had an accruing factor of 1 from the begining. This accounts for that.
    return accruingFactor[_account] + initialization;
  }

  /**
  * @dev Delegate the UBI stream to another recipient than the current human
  * @param _newDelegate The new delegate address to delegate stream UBI
  */
  function delegate(address _newDelegate) public {
    // Only humans can delegate their accruance
    require(proofOfHumanity.isRegistered(msg.sender), "The sender is not registered in Proof Of Humanity.");
    require(delegateOf[msg.sender] != _newDelegate, "Cannot set same delegate");
    require(delegateOf[_newDelegate] != msg.sender, "Invalid circular delegation");

    // If previous delegate is set, consolidate the balance, subtract factor from it and set accruedSince to 0.
    address prevDelegate = delegateOf[msg.sender];
    if(prevDelegate != address(0)) {
      // Consolidate balance of previous delegate before clearing it out
      uint256 newSupplyFrom;
      if (accruedSince[prevDelegate] != 0 && accruingFactor[prevDelegate] != 0) {
          newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[prevDelegate])).mul(accruingFactor[prevDelegate]);
          totalSupply = totalSupply.add(newSupplyFrom);
          accruedSince[prevDelegate] = block.timestamp;
      }
      balance[prevDelegate] = balance[prevDelegate].add(newSupplyFrom);
      accruingFactor[prevDelegate] = this.getAccruingFactor(prevDelegate).sub(1);
      accruedSince[prevDelegate] = 0;
      // clear prev delegate
      inverseDelegateOf[prevDelegate] = address(0);
    } 

    // If no delegate was previously set, and destination is not address 0, consolidate the accrued balance of human, set accrued since to 0 and subtract 1 from accruing factor.
    else if(delegateOf[msg.sender] == address(0) && _newDelegate != address(0)) {
      // Consolidate caller balance before delegating
      uint256 newSupplyFrom;
      if (accruedSince[msg.sender] != 0 && accruingFactor[msg.sender] != 0) {
          newSupplyFrom = accruedPerSecond.mul(block.timestamp.sub(accruedSince[msg.sender])).mul(accruingFactor[msg.sender]);
          totalSupply = totalSupply.add(newSupplyFrom);
      }

      accruingFactor[msg.sender] = this.getAccruingFactor(msg.sender).sub(1);
      accruedSince[msg.sender] = 0;
    }
    
    // If destination is address(0), restore accruing to delegator
    address newAccruer = (_newDelegate == address(0)) ? msg.sender : _newDelegate;
    accruingFactor[newAccruer] = this.getAccruingFactor(newAccruer).add(1);
    accruedSince[newAccruer] = block.timestamp;

    // Set new delegate
    delegateOf[msg.sender] = _newDelegate;
    if(_newDelegate != address(0)){
      inverseDelegateOf[_newDelegate] = msg.sender;
    }

    emit DelegateChange(msg.sender, _newDelegate);
  }

  /**
  * @dev Gets the account that is delegate of `_delegator`.
  * @param _delegator The delegator account.
  * @return The current delegate of `_delegator`. If accruing is not delegated, returns address(0).
  **/
  function getDelegateOf(address _delegator) public view returns(address) {
    return delegateOf[_delegator];
  }

  function getInverseDelegateOf(address _delegate) public view returns(address) {
    return inverseDelegateOf[_delegate];
  }


  /*** 
   * EIP-1620 IMPLEMENTATION 
   **/

    // Stores the last stream id used.
     uint256 currentStreamId = 0;

     // All the streams
    mapping(uint256 => Stream) streams;

    mapping(address => uint256[]) delegations;


   function create(address _recipient, address _tokenAddress, uint256 _startBlock, uint256 _stopBlock, uint256 _payment, uint256 _interval) override public {
     require(proofOfHumanity.isRegistered(msg.sender), "The submission is not registered in Proof Of Humanity.");
     require(_tokenAddress == address(this), "Invalid tokenAddress. Can only be UBI");
     require(_interval == 3600, "Interval should be 1 hour (3600)");
     require(_payment <= 1e18, "Cannot delegate more than 1 UBI per hour");
    
      // Increase stream ID
      currentStreamId = currentStreamId.add(1);

      // Create new stream
      streams[currentStreamId] = Stream({
        sender: msg.sender,
        recipient: _recipient,
        tokenAddress: address(this),
        balance: _payment,
        timeFrame: Timeframe({
          start: _startBlock,
          stop: _stopBlock
        }),
        rate: Rate({
          // Payment is by the second. _payment value is UBIs per hour 
           payment: _payment.div(3600),
           interval: 1
        })
      });

      delegations[msg.sender].push(currentStreamId);
    
      emit LogCreate(currentStreamId, msg.sender, _recipient, address(this), _startBlock, _stopBlock, _payment, _interval);
   }

   function getStreamAccruedValue(uint256 streamId) internal returns (uint256) {
     
     // TODO: VALIDATE STREAM EXPIRATION
     uint256 factor = streams[streamId].balance.div(3600);

     // Real accrued value is delegator accrued value * stream UBIs per hour / 1 UBI
     return getAccruedValue(streams[streamId].sender).mul(streams[streamId].balance.div(1e18));      
   }


   /// @dev Returns available funds for the given stream id and address.
    function balanceOf(uint256 _streamId, address _addr) override public view returns(uint256) {
      
      Stream memory stream = streams[_streamId];
      require(stream.recipient == _addr || stream.sender == _addr, 'Address does not belong to stream');
      
      // If it's the delegator, return 0 balance, since it is constantly streaming it's UBI to the delegate 
      // CAUTION: This is only true if the interval is 1 sec. If other interval is used, it must accont for that.
      if(stream.sender == _addr) return 0;

      // Return the actual accrued value of the sender (who is always a registered human) for the recipient.
      uint256 humanAccruedValue = getAccruedValue(stream.sender) * stream.factor;      
      return humanAccruedValue;
    }

}
