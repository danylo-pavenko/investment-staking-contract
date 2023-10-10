import { ethers } from "hardhat";
import {InvestmentTrain, InvestmentTrain__factory, USDT, USDT__factory} from "../typechain-types";

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);

  // Deploy the USDT test token
  const usdt: USDT = await (new USDT__factory(deployer)).deploy();
  await usdt.waitForDeployment();
  
  // Deploy the InvestmentTrain contract with a dummy USDT address for now
  const InvestmentTrainFactory = new InvestmentTrain__factory(deployer);
  const investmentTrain: InvestmentTrain = await InvestmentTrainFactory.deploy(await usdt.getAddress());  // <-- Replace with your USDT address if you have one.
  await investmentTrain.waitForDeployment();
  console.log("InvestmentTrain deployed to:", await investmentTrain.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
