const { default: BigNumber } = require("bignumber.js");
const { expect } = require("chai");
const deploymentParams = require('../deployment-params');
const testUtils = require("./testUtils");

/**
 @summary Tests for UBI.sol
*/
contract('UBI.sol', accounts => {
  describe('UBI Coin and Proof of Humanity', () => {
    before(async () => {
      accounts = await ethers.getSigners();

      [_addresses, mockProofOfHumanity, mockPoster] = await Promise.all([
        Promise.all(accounts.map((account) => account.getAddress())),
        waffle.deployMockContract(
          accounts[0],
          require("../artifacts/contracts/UBI.sol/IProofOfHumanity.json").abi
        ),
        waffle.deployMockContract(
          accounts[9],
          require("../artifacts/contracts/UBI.sol/IPoster.json").abi
        ),
      ]);
      setSubmissionIsRegistered = (submissionID, isRegistered) =>
        mockProofOfHumanity.mock.isRegistered
          .withArgs(submissionID)
          .returns(isRegistered);
      setPost = (content) =>
        mockPoster.mock.post
          .withArgs(content)
          .returns();

      addresses = _addresses;

      UBICoin = await ethers.getContractFactory("UBI");

      ubi = await upgrades.deployProxy(UBICoin,
        [deploymentParams.INITIAL_SUPPLY, deploymentParams.TOKEN_NAME, deploymentParams.TOKEN_SYMBOL, deploymentParams.ACCRUED_PER_SECOND, mockProofOfHumanity.address],
        { initializer: 'initialize', unsafeAllowCustomTypes: true }
      );

      const mockAddress = mockPoster.address;
      await ubi.deployed();

      altProofOfHumanity = await waffle.deployMockContract(accounts[0], require("../artifacts/contracts/UBI.sol/IProofOfHumanity.json").abi);
      altPoster = mockAddress;

      // Set zero address as not registered
      setSubmissionIsRegistered(ethers.constants.AddressZero, false);
    });

    describe("UBI basic use cases", () => {

      it("happy path - return a value previously initialized.", async () => {
        // Check that the value passed to the constructor is set.
        expect((await ubi.accruedPerSecond()).toString()).to.equal(deploymentParams.ACCRUED_PER_SECOND.toString());
      });

      it("happy path - check that the initial `accruedSince` value is 0.", async () => {
        expect((await ubi.accruedSince(addresses[1])).toString()).to.equal('0');
      });

      it("require fail - The submission is not registered in Proof Of Humanity.", async () => {
        // Make sure it reverts if the submission is not registered.
        await setSubmissionIsRegistered(addresses[1], false);
        await expect(
          ubi.startAccruing(addresses[1])
        ).to.be.revertedWith(
          "The submission is not registered in Proof Of Humanity."
        );
      });

      it("happy path - allow registered submissions to start accruing UBI.", async () => {
        // Start accruing UBI and check that the current block number was set.
        await setSubmissionIsRegistered(addresses[1], true);
        await ubi.startAccruing(addresses[1]);
        const accruedSince = await ubi.accruedSince(addresses[1]);
        expect((await ubi.accruedSince(addresses[1])).toString()).to.equal(
          accruedSince.toString()
        );
      });

      it("require fail - The submission is already accruing UBI.", async () => {
        // Make sure it reverts if you try to accrue UBI while already accruing UBI.
        await expect(
          ubi.startAccruing(addresses[1])
        ).to.be.revertedWith("The submission is already accruing UBI.");
      });

      it("happy path - a submission removed from Proof of Humanity no longer accrues value.", async () => {
        await network.provider.send("evm_increaseTime", [7200]);
        await network.provider.send("evm_mine");
        await setSubmissionIsRegistered(addresses[1], false);
        await network.provider.send("evm_increaseTime", [3600]);
        await network.provider.send("evm_mine");
        expect((await ubi.balanceOf(addresses[1])).toString()).to.equal('0');
      });

      it("happy path - a submission with interrupted accruing still keeps withdrawn coins.", async () => {
        await ubi.transfer(addresses[1], 555);
        await setSubmissionIsRegistered(addresses[1], true);
        await network.provider.send("evm_increaseTime", [7200]);
        await network.provider.send("evm_mine");
        await setSubmissionIsRegistered(addresses[1], false);
        await network.provider.send("evm_increaseTime", [7200]);
        await network.provider.send("evm_mine");
        expect((await ubi.balanceOf(addresses[1])).toString()).to.equal('555');
      });

      it("happy path - a submission that natively accrued keeps transfered coins upon interruption.", async () => {
        await setSubmissionIsRegistered(accounts[3].address, true);
        expect((await ubi.balanceOf(accounts[3].address)).toString()).to.equal('0');
        await ubi.startAccruing(accounts[3].address);
        await network.provider.send("evm_increaseTime", [7200]);
        await network.provider.send("evm_mine");
        await ubi.connect(accounts[3]).transfer(addresses[1], 55);
        expect((await ubi.balanceOf(addresses[1])).toString()).to.equal('610');
      });

      it("happy path - check that Mint and Transfer events get called when it corresponds.", async () => {
        const owner = accounts[9];
        const initialBalance = await ubi.balanceOf(owner.address);
        await setSubmissionIsRegistered(owner.address, true);
        await ubi.startAccruing(owner.address);
        await network.provider.send("evm_increaseTime", [1]);
        await network.provider.send("evm_mine");
        expect(await ubi.balanceOf(owner.address)).to.be.above(initialBalance);
        await expect(ubi.connect(owner).transfer(addresses[8], 18000))
          .to.emit(ubi, "Transfer")
        await expect(ubi.connect(owner).burn('199999999966000'))
          .to.emit(ubi, "Transfer")
        await setSubmissionIsRegistered(owner.address, false);
        await expect(ubi.connect(owner).burn('100000000000000'))
          .to.emit(ubi, "Transfer")
        expect(await ubi.balanceOf(owner.address)).to.be.at.least(3000);
      });

      it("require fail - The submission is still registered in Proof Of Humanity.", async () => {
        // Make sure it reverts if the submission is still registered.
        await setSubmissionIsRegistered(addresses[6], true);
        await ubi.startAccruing(addresses[6]);
        await expect(
          ubi.reportRemoval(addresses[6])
        ).to.be.revertedWith(
          "The submission is still registered in Proof Of Humanity."
        );
      });

      it("happy path - allows anyone to report a removed submission for their accrued UBI.", async () => {
        // Report submission and verify that `accruingSinceBlock` was reset.
        // Also verify that the accrued UBI was sent correctly.
        await ubi.accruedSince(addresses[1]);
        await ubi.reportRemoval(addresses[1]);
        expect((await ubi.accruedSince(addresses[1])).toString()).to.equal('0');
      });

      it("happy path - returns 0 for submissions that are not accruing UBI.", async () => {
        expect((await ubi.getAccruedValue(addresses[5])).toString()).to.equal('0');
      });

      it("happy path - allow governor to change `proofOfHumanity`.", async () => {
        // Make sure it reverts if we are not the governor.
        await expect(
          ubi.connect(accounts[1]).changeProofOfHumanity(altProofOfHumanity.address)
        ).to.be.revertedWith("The caller is not the governor.");

        // Set the value to an alternative proof of humanity registry
        const originalProofOfHumanity = await ubi.proofOfHumanity();
        await ubi.changeProofOfHumanity(altProofOfHumanity.address);
        expect(await ubi.proofOfHumanity()).to.equal(altProofOfHumanity.address);
        expect(await ubi.proofOfHumanity()).to.not.equal(originalProofOfHumanity);

        await ubi.changeProofOfHumanity(originalProofOfHumanity)
      });

      it("happy path - allow to burn and post.", async () => {
        await setSubmissionIsRegistered(addresses[0], true);
        await setPost('hello world');
        const previousBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
        await ubi.burnAndPost(ethers.utils.parseEther("0.01"), altPoster, 'hello world');
        const newBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
        expect(newBalance.toNumber()).to.lessThan(previousBalance.toNumber());
      });
    });
  });

  describe("UBI accruing delegation", () => {

    before(async () => {
      // Restore original PoH
      await ubi.changeProofOfHumanity(mockProofOfHumanity.address);
    });

    it("happy path - Accruing factor is correctly updated for the delegated address and the delegator", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);

      // Initially, human has an accruing factor of 1
      const initialHumanAccruingFactor = new BigNumber((await ubi.getAccruingFactor(addresses[0])).toString()).toNumber();
      // // New Delegate has an accruing factor of 0.
      const initialDelegateAccruingFactor = new BigNumber((await ubi.getAccruingFactor(addresses[1])).toString()).toNumber();

      expect(initialHumanAccruingFactor).to.eq(1);
      expect(initialDelegateAccruingFactor).to.eq(0);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      // Restore delegation
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);
    });

    it("happy path - Accruing factor is correctly restored to the human after delegating to address 0", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);


      // Initially, human has an accruing factor of 1
      expect(new BigNumber((await ubi.getAccruingFactor(addresses[0])).toString()).toNumber()).to.eq(1);
      // New Delegate has an accruing factor of 0.
      expect(new BigNumber((await ubi.getAccruingFactor(addresses[1])).toString()).toNumber()).to.eq(0);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      // Wait 1 hour
      await testUtils.timeForward(3600, network);

      // Restore delegation to zero
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);
      
    });

    it("happy path - 1 hour after delegating, human balance should not change and delegate balance should increase by 1 UBI", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);
      
      const initialHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])));
      const initialDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])));

      await testUtils.timeForward(3600, network);

      const newHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      const newDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());

      expect(newHumanBalance.eq(initialHumanBalance), "Human balance should not change after setting a delegate.");
      expect(newDelegateBalance.eq(BigNumber.sum(initialDelegateBalance, ethers.utils.parseEther("1"))), "New delegate balance should have a balance after being set as delegate");
      
      // Restore delegation to zero
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);
    });

    it("happy path - 1 hour after restoring delegation, human balance should normally ncrease by 1 UBI and delegate balance should not change", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);
      
      // Clear delegation
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);

      const initialHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])));
      const initialDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])));


      // Wait 1 hour
      await testUtils.timeForward(3600, network);

      const newHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      const newDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());

      expect(newHumanBalance.eq(BigNumber.sum(initialHumanBalance, ethers.utils.parseEther("1"))), "Human balance should increase by 1 UBI after 1 hour of clearing delegate.");
      expect(newDelegateBalance.eq(initialDelegateBalance), "New delegate balance should not change after being cleared out as delegate");
    });

    it("fail path - delegating accruance to same delegate should fail ", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      expect(ubi.connect(accounts[0]).delegate(addresses[1])).to.be.revertedWith("Cannot set same delegate");

      // Restore delegation to zero
      await ubi.connect(accounts[0]).delegate(ethers.constants.AddressZero);
    });

    it("happy path - after 1 hour of delegating to another human, delegate human balance should increase by 2 UBI", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], true);

      // // Delegate and wait until tx is mined
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      const initialHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      const initialDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());
    

      // Wait 1 hour
      await testUtils.timeForward(3600, network);
      
      // Human should not increase its balance if delegated stream
      const newHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      expect(initialHumanBalance.toString()).to.eq(newHumanBalance.toString(), "Delegator human should not receive UBIs while delegating accruing");
      
      // Delegate human should receive their own UBI and the delegate UBI (2 UBI per hour)
      const newDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());
      const expectedDelegateBalance = initialDelegateBalance.plus(ethers.utils.parseEther("2").toString());
      expect(newDelegateBalance.toNumber()).to.be.at.least(expectedDelegateBalance.toNumber(), "After 1 hour of delegating a human, delegate should receive 2 UBI per hour");

      // Restore delegation to zero
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);

    });


    it("happy path - after delegating and restoring delegation, delegate should keep it's UBI", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      const initialHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      const initialDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());

      await testUtils.timeForward(3600, network);

      const newHumanBalance = new BigNumber((await ubi.balanceOf(addresses[0])).toString());
      const newDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());

      expect(initialHumanBalance.toNumber()).to.eq(newHumanBalance.toNumber(), "Delegator human should not receive UBIs while delegating accruing");
      expect(newDelegateBalance.toNumber()).to.be.at.least(initialDelegateBalance.plus(ethers.utils.parseEther("2").toString()).toNumber(), "After 1 hour of delegating a human, delegate should receive 2 UBI per hour");

      // Clear delegation
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);
    });

    it("happy path - after delegation is cleared, delegate should be able to keep and spend its balance", async () => {
      setSubmissionIsRegistered(addresses[0], true);
      setSubmissionIsRegistered(addresses[1], false);
      setSubmissionIsRegistered(addresses[8], false);

      // Get initial UBI balance of delegate
      const initialDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());

      // Delegate to account 1
      await testUtils.delegateAndCheck(accounts[0], addresses[1], ubi);

      // Wait 1 hour
      await testUtils.timeForward(3600, network);
      
      // Balance of delegate after an hour
      const newDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());
      expect(newDelegateBalance.toNumber()).to.be.at.least(initialDelegateBalance.plus(ethers.utils.parseEther("1").toString()).toNumber(), "After 1 hour of delegating a human, delegate should receive 1 UBI per hour");

      // Restore delegation
      await testUtils.delegateAndCheck(accounts[0], ethers.constants.AddressZero, ubi);

      // Balance of delegate after being removed as delegate
      const afterClearedDelegationBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());
      expect(afterClearedDelegationBalance.eq(newDelegateBalance), "After clearing delegation, previous delegate should keep the UBI");

      const valueToTransfer = new BigNumber(ethers.utils.parseEther("0.1").toString());
      const prevRecipientBalance = new BigNumber((await ubi.balanceOf(addresses[8])).toString());
      await ubi.connect(accounts[1]).transfer(addresses[8], valueToTransfer.toString());
      const afterTransferDelegateBalance = new BigNumber((await ubi.balanceOf(addresses[1])).toString());
      const newRecipientBalance = new BigNumber((await ubi.balanceOf(addresses[8])).toString());
      expect(newRecipientBalance.toNumber()).to.eq(prevRecipientBalance.plus(valueToTransfer).toNumber(), "Recipient did not receive the correct value.")

      expect(afterTransferDelegateBalance.toNumber()).to.eq(afterClearedDelegationBalance.minus(valueToTransfer).toNumber(), "Incorrect new balance after transfer");



      // await expect(new BigNumber(ubi.balanceOf(addresses[8])).toNumber()).to.emit(ubi, "Transfer")
      // await setSubmissionIsRegistered(owner.address, false);
      // await expect(ubi.connect(owner).burn('100000000000000'))
      //   .to.emit(ubi, "Transfer")
      // expect(await ubi.balanceOf(owner.address)).to.be.at.least(3000);
    });
  })
});
