const { default: BigNumber } = require("bignumber.js");
const { ethers, expect } = require("hardhat");

module.exports = {
  async delegateAndCheck(fromAccount, toAddress, ubi) {
    
    const previousDelegate = await ubi.getDelegateOf(fromAccount.address);
    const prevDelegateAccruingFactor = new BigNumber((await ubi.getAccruingFactor(previousDelegate)).toString());
    const newDelegatePrevAccruingFactor = new BigNumber((await ubi.getAccruingFactor(toAddress)).toString());

    // Delegate fromAccount to toAddress
    await ubi.connect(fromAccount).delegate(toAddress);
    expect(await ubi.getDelegateOf(fromAccount.address)).to.eq(toAddress, "Invalid delegate of");

    const newDelegateAccruingFactor =  new BigNumber((await ubi.getAccruingFactor(toAddress)).toString());

    if (toAddress !== ethers.constants.AddressZero) {
      // Human should have an accruing factor of 0
      expect(new BigNumber((await ubi.getAccruingFactor(fromAccount.address)).toString()).toNumber()).to.eq(0, "Human should have an accruing factor of 0 after delegating.");
      // Delegate should have an accruing factor of 1
      expect(newDelegateAccruingFactor.toNumber()).to.eq(newDelegatePrevAccruingFactor.plus(1).toNumber(), `Delegate ${toAddress} should have its accruing factor increased by 1 after being delegated`);
    } else {
      // Human should have an accruing factor of 1 restored
      expect(new BigNumber((await ubi.getAccruingFactor(fromAccount.address)).toString()).toNumber()).to.eq(1, "Human should have an accruing factor of 1 after setting delegate as address 0.");
      // Previous delegate should have accruing factor reduced by 1
      expect(new BigNumber((await ubi.getAccruingFactor(previousDelegate)).toString()).toNumber()).to.eq(prevDelegateAccruingFactor.minus(1).toNumber(), "Previous delegate should have its accruing factor reduced by 1 after being removed as delegate.");
    }
  },

  async timeForward(seconds, network) {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
  }
}