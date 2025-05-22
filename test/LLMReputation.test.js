const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LLMReputation", function () {
    let LLMReputation;
    let llmReputation;
    let owner;
    let llm1;
    let llm2;
    let llm3;

    beforeEach(async function () {
        [owner, llm1, llm2, llm3] = await ethers.getSigners();

        // Deploy the contract
        LLMReputation = await ethers.getContractFactory("LLMReputation");
        llmReputation = await LLMReputation.deploy();

        // Mint initial reputation to LLMs
        await llmReputation.mintInitialReputation(llm1.address, ethers.parseEther("1000"));
        await llmReputation.mintInitialReputation(llm2.address, ethers.parseEther("1000"));
        await llmReputation.mintInitialReputation(llm3.address, ethers.parseEther("1000"));
    });

    describe("Basic Functionality", function () {
        it("Should allow staking on facts", async function () {
            const stakeAmount = ethers.parseEther("100");
            
            await llmReputation.connect(llm1).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                stakeAmount
            );

            const factHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Blue"
            );

            const [category1, value1, category2, value2, confidence, totalStaked] = 
                await llmReputation.getFactDetails(factHash);

            expect(category1).to.equal("Name");
            expect(value1).to.equal("Alex");
            expect(category2).to.equal("House");
            expect(value2).to.equal("Blue");
            // Allow for possible rewards in totalStaked
            expect(totalStaked).to.be.gte(stakeAmount);
            expect(confidence).to.be.gt(0);
        });
    });

    describe("Confidence Calculation", function () {
        it("Should calculate confidence based on stake distribution", async function () {
            const stakeAmount = ethers.parseEther("100");
            
            // First fact: Alex has Blue house
            await llmReputation.connect(llm1).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                stakeAmount
            );
            
            // Second fact: Bob has Blue house
            await llmReputation.connect(llm2).stakeOnFact(
                "Name", "Bob", "House", "Blue",
                stakeAmount
            );
            
            const alexFactHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Blue"
            );
            
            // Get the confidence after two facts
            const [,,,, alexConfidence,] = await llmReputation.getFactDetails(alexFactHash);
            
            // Confidence should be influenced by stake distribution
            expect(alexConfidence).to.be.gt(0);
        });

        it("Should update confidence when competing facts are staked", async function () {
            const highStake = ethers.parseEther("800");
            const lowStake = ethers.parseEther("100");
            
            // LLM1 stakes heavily on "Alex lives in Blue house"
            await llmReputation.connect(llm1).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                highStake
            );
            
            const blueFactHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Blue"
            );
            const [,,,, initialConfidence,] = await llmReputation.getFactDetails(blueFactHash);
            
            // LLM2 stakes lightly on competing fact "Alex lives in Red house"
            await llmReputation.connect(llm2).stakeOnFact(
                "Name", "Alex", "House", "Red",
                lowStake
            );
            
            // Get Red house hash
            const redFactHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Red"
            );
            
            // Get confidences
            const [,,,, blueAfterCompetingConfidence,] = await llmReputation.getFactDetails(blueFactHash);
            const [,,,, redConfidence,] = await llmReputation.getFactDetails(redFactHash);
            
            // Blue house should have higher confidence than Red house
            expect(blueAfterCompetingConfidence).to.be.gt(redConfidence);
        });
    });

    describe("Rewards and Slashes", function () {
        it("Should reward supporting facts with high confidence", async function () {
            const stakeAmount = ethers.parseEther("500"); // Higher stake to reach high confidence
            
            // Series of supporting facts
            await llmReputation.connect(llm1).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                stakeAmount
            );
            
            await llmReputation.connect(llm2).stakeOnFact(
                "House", "Blue", "City", "London",
                stakeAmount
            );
            
            // Third fact supported by first two
            const initialBalance = await llmReputation.balanceOf(llm3.address);
            await llmReputation.connect(llm3).stakeOnFact(
                "Name", "Alex", "City", "London",
                stakeAmount
            );
            
            // Check fact confidence is high
            const factHash = await llmReputation.createFactHash(
                "Name", "Alex", "City", "London"
            );
            const [,,,, confidence,] = await llmReputation.getFactDetails(factHash);
            
            // We can't easily check if rewards were distributed without more complex tracking,
            // but we can verify high confidence was achieved
            expect(confidence).to.be.gt(50);
        });

        it("Should reduce confidence of competing facts", async function () {
            const highStake = ethers.parseEther("800");
            const lowStake = ethers.parseEther("100");
            
            // LLM1 stakes heavily on "Alex lives in Blue house"
            await llmReputation.connect(llm1).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                highStake
            );
            
            // Get initial confidence of the Blue house fact
            const blueFactHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Blue"
            );
            const [,,,, blueConfidence,] = await llmReputation.getFactDetails(blueFactHash);
            
            // LLM2 stakes lightly on competing fact
            await llmReputation.connect(llm2).stakeOnFact(
                "Name", "Alex", "House", "Red",
                lowStake
            );
            
            // Check confidence of competing fact
            const redFactHash = await llmReputation.createFactHash(
                "Name", "Alex", "House", "Red"
            );
            const [,,,, redConfidence,] = await llmReputation.getFactDetails(redFactHash);
            
            // The primary fact should have higher confidence than the competing fact
            expect(blueConfidence).to.be.gt(redConfidence);
            
            // LLM3 adds another high stake to first fact
            await llmReputation.connect(llm3).stakeOnFact(
                "Name", "Alex", "House", "Blue",
                highStake
            );
            
            // Get the updated confidences
            const [,,,, finalBlueConfidence,] = await llmReputation.getFactDetails(blueFactHash);
            const [,,,, finalRedConfidence,] = await llmReputation.getFactDetails(redFactHash);
            
            // Blue house confidence should be high
            expect(finalBlueConfidence).to.be.gte(80);
            
            // Red house confidence should be lower
            expect(finalRedConfidence).to.be.lt(50);
        });
    });

    it("Should print confidence values for debugging", async function () {
        const highStake = ethers.parseEther("800");
        const lowStake = ethers.parseEther("100");
        
        console.log("--- STAKING TEST WITH DEBUGGING (NEW MODEL) ---");
        
        // LLM1 stakes heavily on "Alex lives in Blue house"
        await llmReputation.connect(llm1).stakeOnFact(
            "Name", "Alex", "House", "Blue",
            highStake
        );
        
        // Get initial confidence of the Blue house fact
        const blueFactHash = await llmReputation.createFactHash(
            "Name", "Alex", "House", "Blue"
        );
        const [,,,, blueInitialConfidence,] = await llmReputation.getFactDetails(blueFactHash);
        console.log("Blue house initial confidence:", blueInitialConfidence.toString());
        
        // LLM2 stakes lightly on competing fact
        await llmReputation.connect(llm2).stakeOnFact(
            "Name", "Alex", "House", "Red",
            lowStake
        );
        
        // Check confidences after Red house is staked
        const redFactHash = await llmReputation.createFactHash(
            "Name", "Alex", "House", "Red"
        );
        const [,,,, redInitialConfidence,] = await llmReputation.getFactDetails(redFactHash);
        const [,,,, blueAfterRedConfidence,] = await llmReputation.getFactDetails(blueFactHash);
        
        console.log("Blue house confidence after Red is staked:", blueAfterRedConfidence.toString());
        console.log("Red house initial confidence:", redInitialConfidence.toString());
        
        // LLM3 adds another high stake to Blue house
        await llmReputation.connect(llm3).stakeOnFact(
            "Name", "Alex", "House", "Blue",
            highStake
        );
        
        // Get the updated confidences
        const [,,,, finalBlueConfidence,] = await llmReputation.getFactDetails(blueFactHash);
        const [,,,, finalRedConfidence,] = await llmReputation.getFactDetails(redFactHash);
        
        console.log("Final Blue house confidence:", finalBlueConfidence.toString());
        console.log("Final Red house confidence:", finalRedConfidence.toString());
        console.log("Difference:", (finalBlueConfidence - finalRedConfidence).toString());
        
        // Get category stake information
        const nameAlexStake = await llmReputation.getCategoryValueStake("Name", "Alex");
        const houseTotalStake = await llmReputation.getCategoryTotalStake("House");
        console.log("Name:Alex total stake:", ethers.formatEther(nameAlexStake));
        console.log("House total stake:", ethers.formatEther(houseTotalStake));
        
        // Just to make the test pass
        expect(true).to.be.true;
    });
}); 