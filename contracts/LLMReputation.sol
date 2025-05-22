// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LLMReputation is ERC20, Ownable {
    struct Fact {
        string category1;
        string value1;
        string category2;
        string value2;
        uint256 confidence;         // Current confidence score (0-100)
        uint256 totalStaked;        // Total tokens staked on this fact
        mapping(address => uint256) stakes;  // Individual stakes per LLM
        bool exists;
    }

    // Mapping from fact hash to Fact
    mapping(bytes32 => Fact) public facts;
    // Array to track all facts
    bytes32[] public allFactHashes;
    
    // Track total stake across all facts in a category
    mapping(string => mapping(string => uint256)) public categoryValueTotalStake;
    mapping(string => uint256) public categoryTotalStake;
    
    // Minimum stake required to submit a fact
    uint256 public constant MINIMUM_STAKE = 100 * 10**18; // 100 tokens
    
    event FactStaked(
        bytes32 indexed factHash,
        string category1,
        string value1,
        string category2,
        string value2,
        address indexed staker,
        uint256 amount,
        uint256 newConfidence
    );
    
    event ConfidenceUpdated(
        bytes32 indexed factHash,
        uint256 oldConfidence,
        uint256 newConfidence
    );
    
    event ReputationRewarded(
        address indexed staker,
        bytes32 indexed factHash,
        uint256 amount
    );
    
    event ReputationSlashed(
        address indexed staker,
        bytes32 indexed factHash,
        uint256 amount
    );

    constructor() ERC20("LLM Reputation", "LLMR") Ownable(msg.sender) {}

    // Only owner can mint initial reputation to LLMs
    function mintInitialReputation(address llm, uint256 amount) external onlyOwner {
        _mint(llm, amount);
    }

    function createFactHash(
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(category1, value1, category2, value2));
    }
    
    function stakeOnFact(
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2,
        uint256 stakeAmount
    ) external {
        require(stakeAmount >= MINIMUM_STAKE, "Insufficient stake");
        require(balanceOf(msg.sender) >= stakeAmount, "Insufficient balance");

        bytes32 factHash = createFactHash(category1, value1, category2, value2);

        // Transfer stake from submitter to contract
        transfer(address(this), stakeAmount);

        // If new fact, initialize and add to array
        if (!facts[factHash].exists) {
            facts[factHash].category1 = category1;
            facts[factHash].value1 = value1;
            facts[factHash].category2 = category2;
            facts[factHash].value2 = value2;
            facts[factHash].exists = true;
            facts[factHash].confidence = 50; // Start at 50% confidence
            allFactHashes.push(factHash);
        }

        // Update fact stakes
        uint256 oldConfidence = facts[factHash].confidence;
        facts[factHash].totalStaked += stakeAmount;
        facts[factHash].stakes[msg.sender] += stakeAmount;
        
        // Update category-value stakes
        categoryValueTotalStake[category1][value1] += stakeAmount;
        categoryValueTotalStake[category2][value2] += stakeAmount;
        categoryTotalStake[category1] += stakeAmount;
        categoryTotalStake[category2] += stakeAmount;
        
        // Recalculate confidence based on stake distribution
        _recalculateConfidence(factHash);
        
        emit FactStaked(
            factHash, 
            category1, 
            value1, 
            category2, 
            value2, 
            msg.sender, 
            stakeAmount,
            facts[factHash].confidence
        );
        
        // Update competing facts' confidence
        _updateCompetingFactsConfidence(factHash);
        
        // Potentially reward supporters if confidence is high
        if (facts[factHash].confidence > 80) {
            _rewardSupporters(factHash);
        }
    }
    
    function _recalculateConfidence(bytes32 factHash) internal {
        Fact storage fact = facts[factHash];
        uint256 oldConfidence = fact.confidence;
        
        // Calculate ratio of stake on this fact vs competing facts
        uint256 totalCompetingStake = 0;
        uint256 competingFactCount = 0;
        
        for (uint256 i = 0; i < allFactHashes.length; i++) {
            bytes32 otherHash = allFactHashes[i];
            Fact storage otherFact = facts[otherHash];
            
            if (_isCompeting(fact, otherFact)) {
                totalCompetingStake += otherFact.totalStaked;
                competingFactCount++;
            }
        }
        
        // Add this fact's stake to the total
        totalCompetingStake += fact.totalStaked;
        
        // Calculate confidence as percentage of total competing stake
        // With a minimum of 5% and maximum of 95% to prevent 0% or 100% confidence
        if (totalCompetingStake > 0) {
            uint256 rawConfidence = (fact.totalStaked * 100) / totalCompetingStake;
            fact.confidence = 5 + ((rawConfidence * 90) / 100); // Scale to 5-95% range
        } else {
            fact.confidence = 50; // Default confidence for new facts
        }
        
        // Cap at 95 to allow room for competing theories
        if (fact.confidence > 95) {
            fact.confidence = 95;
        }
        
        if (oldConfidence != fact.confidence) {
            emit ConfidenceUpdated(factHash, oldConfidence, fact.confidence);
        }
    }
    
    function _updateCompetingFactsConfidence(bytes32 factHash) internal {
        Fact storage targetFact = facts[factHash];
        
        for (uint256 i = 0; i < allFactHashes.length; i++) {
            bytes32 otherHash = allFactHashes[i];
            if (otherHash == factHash) continue;
            
            Fact storage otherFact = facts[otherHash];
            
            // Check if facts are competing
            if (_isCompeting(targetFact, otherFact)) {
                uint256 oldConfidence = otherFact.confidence;
                
                // Stronger confidence reduction:
                // Impact is proportional to the ratio of stakes
                uint256 stakeRatio = (targetFact.totalStaked * 100) / 
                    (targetFact.totalStaked + otherFact.totalStaked);
                
                // Ensure we drop at least 5% confidence
                uint256 confidenceDrop = stakeRatio > 5 ? stakeRatio : 5;
                
                // Apply confidence drop
                if (confidenceDrop >= otherFact.confidence) {
                    otherFact.confidence = 0;
                } else {
                    otherFact.confidence -= confidenceDrop;
                }
                
                // Emit update event
                if (oldConfidence != otherFact.confidence) {
                    emit ConfidenceUpdated(otherHash, oldConfidence, otherFact.confidence);
                }
                
                // If confidence drops below 20%, slash some stake
                if (otherFact.confidence < 20) {
                    _slashLowConfidenceFact(otherHash);
                }
            }
        }
    }
    
    function _slashLowConfidenceFact(bytes32 factHash) internal {
        Fact storage fact = facts[factHash];
        
        // Slash 10% of total stake
        uint256 slashAmount = fact.totalStaked / 10;
        
        if (slashAmount > 0) {
            fact.totalStaked -= slashAmount;
            
            // Update category totals
            categoryValueTotalStake[fact.category1][fact.value1] -= slashAmount;
            categoryValueTotalStake[fact.category2][fact.value2] -= slashAmount;
            categoryTotalStake[fact.category1] -= slashAmount;
            categoryTotalStake[fact.category2] -= slashAmount;
            
            emit ReputationSlashed(address(0), factHash, slashAmount);
        }
    }
    
    function _rewardSupporters(bytes32 factHash) internal {
        Fact storage fact = facts[factHash];
        
        // Reward is 5% of total stake
        uint256 rewardAmount = fact.totalStaked / 20;
        
        if (rewardAmount > 0) {
            // In a real implementation, you'd distribute to stakers
            // Here we're just minting new tokens as a reward
            _mint(address(this), rewardAmount);
            
            // Add to total stake
            fact.totalStaked += rewardAmount;
            
            // Update category totals
            categoryValueTotalStake[fact.category1][fact.value1] += rewardAmount;
            categoryValueTotalStake[fact.category2][fact.value2] += rewardAmount;
            categoryTotalStake[fact.category1] += rewardAmount;
            categoryTotalStake[fact.category2] += rewardAmount;
            
            emit ReputationRewarded(address(0), factHash, rewardAmount);
        }
    }
    
    function _isCompeting(Fact storage fact1, Fact storage fact2) internal view returns (bool) {
        // Facts compete if:
        // 1. They share the same category1 and value1 but have different category2/value2
        // 2. They share the same category2 and value2 but have different category1/value1
        // 3. They have the same categories but different values
        
        bool sameCategories = (
            keccak256(abi.encodePacked(fact1.category1, fact1.category2)) == 
            keccak256(abi.encodePacked(fact2.category1, fact2.category2))
        );
        
        bool sameFirstHalf = (
            keccak256(abi.encodePacked(fact1.category1, fact1.value1)) == 
            keccak256(abi.encodePacked(fact2.category1, fact2.value1))
        );
        
        bool sameSecondHalf = (
            keccak256(abi.encodePacked(fact1.category2, fact1.value2)) == 
            keccak256(abi.encodePacked(fact2.category2, fact2.value2))
        );
        
        return (
            (sameCategories && 
             keccak256(abi.encodePacked(fact1.value1, fact1.value2)) != 
             keccak256(abi.encodePacked(fact2.value1, fact2.value2))) ||
            (sameFirstHalf && 
             keccak256(abi.encodePacked(fact1.category2, fact1.value2)) != 
             keccak256(abi.encodePacked(fact2.category2, fact2.value2))) ||
            (sameSecondHalf && 
             keccak256(abi.encodePacked(fact1.category1, fact1.value1)) != 
             keccak256(abi.encodePacked(fact2.category1, fact2.value1)))
        );
    }
    
    function _isSupporting(Fact storage fact1, Fact storage fact2) internal view returns (bool) {
        // Facts support each other if:
        // 1. They are identical (same categories and values)
        // 2. They share values that create a logical chain
        
        // Check for identical facts
        if (keccak256(abi.encodePacked(fact1.category1, fact1.value1, fact1.category2, fact1.value2)) == 
            keccak256(abi.encodePacked(fact2.category1, fact2.value1, fact2.category2, fact2.value2))) {
            return true;
        }
        
        // Check for chained facts (A->B and B->C supports A->C)
        if ((keccak256(abi.encodePacked(fact1.category2, fact1.value2)) == 
             keccak256(abi.encodePacked(fact2.category1, fact2.value1))) ||
            (keccak256(abi.encodePacked(fact1.category1, fact1.value1)) == 
             keccak256(abi.encodePacked(fact2.category2, fact2.value2)))) {
            return true;
        }
        
        return false;
    }

    function getFactDetails(bytes32 factHash) external view returns (
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2,
        uint256 confidence,
        uint256 totalStaked
    ) {
        Fact storage fact = facts[factHash];
        return (
            fact.category1,
            fact.value1,
            fact.category2,
            fact.value2,
            fact.confidence,
            fact.totalStaked
        );
    }
    
    function getFactConfidence(
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2
    ) external view returns (uint256 confidence) {
        bytes32 factHash = createFactHash(category1, value1, category2, value2);
        return facts[factHash].confidence;
    }

    function getCategoryValueStake(string memory category, string memory value) external view returns (uint256) {
        return categoryValueTotalStake[category][value];
    }
    
    function getCategoryTotalStake(string memory category) external view returns (uint256) {
        return categoryTotalStake[category];
    }
    
    function getStake(bytes32 factHash, address staker) external view returns (uint256) {
        return facts[factHash].stakes[staker];
    }

    function _recalculateAllConfidences() internal {
        // For each category, recalculate all values' confidence to sum to 100%
        string[] memory processedCategories = new string[](allFactHashes.length * 2);
        uint256 processedCount = 0;
        
        // First pass: identify all unique categories
        for (uint256 i = 0; i < allFactHashes.length; i++) {
            Fact storage fact = facts[allFactHashes[i]];
            
            bool found1 = false;
            bool found2 = false;
            
            for (uint256 j = 0; j < processedCount; j++) {
                if (keccak256(abi.encodePacked(processedCategories[j])) == 
                    keccak256(abi.encodePacked(fact.category1))) {
                    found1 = true;
                }
                if (keccak256(abi.encodePacked(processedCategories[j])) == 
                    keccak256(abi.encodePacked(fact.category2))) {
                    found2 = true;
                }
            }
            
            if (!found1) {
                processedCategories[processedCount++] = fact.category1;
            }
            if (!found2) {
                processedCategories[processedCount++] = fact.category2;
            }
        }
        
        // Second pass: normalize confidence for each category
        for (uint256 i = 0; i < processedCount; i++) {
            string memory category = processedCategories[i];
            
            // Get all values for this category and their stakes
            uint256 valueCount = 0;
            string[] memory values = new string[](allFactHashes.length);
            uint256[] memory valueStakes = new uint256[](allFactHashes.length);
            
            for (uint256 j = 0; j < allFactHashes.length; j++) {
                Fact storage fact = facts[allFactHashes[j]];
                
                if (keccak256(abi.encodePacked(fact.category1)) == 
                    keccak256(abi.encodePacked(category))) {
                    // Find if value already exists
                    bool found = false;
                    for (uint256 k = 0; k < valueCount; k++) {
                        if (keccak256(abi.encodePacked(values[k])) == 
                            keccak256(abi.encodePacked(fact.value1))) {
                            found = true;
                            valueStakes[k] += fact.totalStaked;
                            break;
                        }
                    }
                    
                    if (!found) {
                        values[valueCount] = fact.value1;
                        valueStakes[valueCount] = fact.totalStaked;
                        valueCount++;
                    }
                }
                
                if (keccak256(abi.encodePacked(fact.category2)) == 
                    keccak256(abi.encodePacked(category))) {
                    // Find if value already exists
                    bool found = false;
                    for (uint256 k = 0; k < valueCount; k++) {
                        if (keccak256(abi.encodePacked(values[k])) == 
                            keccak256(abi.encodePacked(fact.value2))) {
                            found = true;
                            valueStakes[k] += fact.totalStaked;
                            break;
                        }
                    }
                    
                    if (!found) {
                        values[valueCount] = fact.value2;
                        valueStakes[valueCount] = fact.totalStaked;
                        valueCount++;
                    }
                }
            }
            
            // Calculate total stake for this category
            uint256 totalCategoryStake = 0;
            for (uint256 j = 0; j < valueCount; j++) {
                totalCategoryStake += valueStakes[j];
            }
            
            // Skip if no stake yet
            if (totalCategoryStake == 0) continue;
            
            // Update confidence based on percentage of stake
            for (uint256 j = 0; j < allFactHashes.length; j++) {
                Fact storage fact = facts[allFactHashes[j]];
                
                if (keccak256(abi.encodePacked(fact.category1)) == 
                    keccak256(abi.encodePacked(category))) {
                    // Find value's stake
                    for (uint256 k = 0; k < valueCount; k++) {
                        if (keccak256(abi.encodePacked(values[k])) == 
                            keccak256(abi.encodePacked(fact.value1))) {
                            uint256 valuePercentage = (valueStakes[k] * 100) / totalCategoryStake;
                            // Average with current confidence for smoother transitions
                            fact.confidence = (fact.confidence + valuePercentage) / 2;
                            break;
                        }
                    }
                }
                
                if (keccak256(abi.encodePacked(fact.category2)) == 
                    keccak256(abi.encodePacked(category))) {
                    // Find value's stake
                    for (uint256 k = 0; k < valueCount; k++) {
                        if (keccak256(abi.encodePacked(values[k])) == 
                            keccak256(abi.encodePacked(fact.value2))) {
                            uint256 valuePercentage = (valueStakes[k] * 100) / totalCategoryStake;
                            // Average with current confidence for smoother transitions
                            fact.confidence = (fact.confidence + valuePercentage) / 2;
                            break;
                        }
                    }
                }
            }
        }
    }
} 