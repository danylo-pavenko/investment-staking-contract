import { ethers } from "hardhat";
import { expect } from "chai";
import { Signer } from "ethers";
import { InvestmentTrain, InvestmentTrain__factory, USDT, USDT__factory } from "../typechain-types";

describe("InvestmentTrain", function() {
    let investmentTrain: InvestmentTrain;
    let usdt: USDT;
    let owner: Signer;
    let addr1: Signer;
    let addr2: Signer;

    beforeEach(async function() {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy a mock USDT contract for testing
        usdt = await (new USDT__factory(owner)).deploy();
        await usdt.waitForDeployment();

        // Deploy the InvestmentTrain contract
        const InvestmentTrainFactory = new InvestmentTrain__factory(owner);
        investmentTrain = await InvestmentTrainFactory.deploy(await usdt.getAddress());
        await investmentTrain.waitForDeployment();
    });

    describe("Investment flow", function() {
        it("Should allow investments in a train and compute available dividends", async function() {
            // Create a new train
            await investmentTrain.connect(owner).createNewTrain(1000 * 10**6, 3000); // 1000 USDT minimum, 30% annual rate

            // Mint some USDT for addr1 and addr2
            await usdt.mint(await addr1.getAddress(), 2000 * 10**6); // 2000 USDT
            await usdt.mint(await addr2.getAddress(), 500 * 10**6);  // 500 USDT

            // Approve the InvestmentTrain contract to spend USDT
            await usdt.connect(addr1).approve(await investmentTrain.getAddress(), 2000 * 10**6);
            await usdt.connect(addr2).approve(await investmentTrain.getAddress(), 500 * 10**6);

            // Invest in trainId 1
            await investmentTrain.connect(addr1).invest(1, 1500 * 10**6); // 1500 USDT
            await investmentTrain.connect(addr2).invest(1, 500 * 10**6);  // 500 USDT

            // Check total equity of train
            const totalEquity = await investmentTrain.getTotalEquity(1);
            expect(totalEquity).to.equal(2000 * 10**6); // 2000 USDT in total

            // Start the train
            await investmentTrain.connect(owner).startTrain(1);

            // Fast-forward 31 days to make dividends available (this is a Hardhat feature)
            await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine");

            // Check available dividends for addr1
            const availableDividends = await investmentTrain.getTotalAvailableDividends(1, await addr1.getAddress());
            expect(availableDividends).to.be.closeTo(37.5 * 10**6, 1 * 10**6);  // Roughly 37.5 USDT
        });
        it("Should allow investments in a train, claim dividends, and then withdraw the investment", async function() {
            // Create a new train
            await investmentTrain.connect(owner).createNewTrain(1000 * 10**6, 3000); // 1000 USDT minimum, 30% annual rate
        
            // Mint some USDT for addr1 and addr2
            await usdt.mint(await addr1.getAddress(), 2000 * 10**6); // 2000 USDT
            await usdt.mint(await addr2.getAddress(), 500 * 10**6);  // 500 USDT
        
            // Approve the InvestmentTrain contract to spend USDT
            await usdt.connect(addr1).approve(await investmentTrain.getAddress(), 2000 * 10**6);
            await usdt.connect(addr2).approve(await investmentTrain.getAddress(), 500 * 10**6);
        
            // Invest in trainId 1
            await investmentTrain.connect(addr1).invest(1, 1500 * 10**6); // 1500 USDT
            await investmentTrain.connect(addr2).invest(1, 500 * 10**6);  // 500 USDT
        
            // Check total equity of train
            const totalEquity = await investmentTrain.getTotalEquity(1);
            expect(totalEquity).to.equal(2000 * 10**6); // 2000 USDT in total
        
            // Start the train
            await investmentTrain.connect(owner).startTrain(1);
        
            // Fast-forward 31 days to make dividends available (this is a Hardhat feature)
            await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]);
            await ethers.provider.send("evm_mine");
        
            // Claim dividends for addr1
            await investmentTrain.connect(addr1).claimDividends(1);
        
            // Check available dividends for addr1
            const dividendsAfterClaim = await investmentTrain.getTotalAvailableDividends(1, await addr1.getAddress());
            expect(dividendsAfterClaim).to.equal(0);  // Should be 0 since dividends were just claimed
        
            // Fast-forward beyond the LOCK_PERIOD to make withdrawals possible
            await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]); // This can be adjusted based on the LOCK_PERIOD value
            await ethers.provider.send("evm_mine");
        
            // Before withdrawal, check the USDT balance of addr1
            const initialBalance = await usdt.balanceOf(await addr1.getAddress());
        
            // Withdraw the investment for addr1
            await investmentTrain.connect(addr1).withdraw(1);
        
            // Check the USDT balance of addr1 after withdrawal
            const finalBalance = await usdt.balanceOf(await addr1.getAddress());
            
            // Ensure the balance increased by the invested amount
            expect(finalBalance - initialBalance).to.equal(1500 * 10**6);
        });
        
    });
});
