const hre = require("hardhat");

async function main() {
  console.log("Deploying LLMReputation contract...");

  const LLMReputation = await hre.ethers.getContractFactory("LLMReputation");
  const llmReputation = await LLMReputation.deploy();

  await llmReputation.waitForDeployment();

  const address = await llmReputation.getAddress();
  console.log("LLMReputation deployed to:", address);

  console.log("Waiting for block confirmations...");
  // Wait for 5 block confirmations for better reliability
  await llmReputation.deploymentTransaction().wait(5);
  
  console.log("Deployment confirmed!");
  
  // Optional: Verify contract on Basescan
  try {
    console.log("Verifying contract on Basescan...");
    await hre.run("verify:verify", {
      address: address,
      constructorArguments: [],
    });
    console.log("Contract verified successfully");
  } catch (error) {
    console.error("Error verifying contract:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 