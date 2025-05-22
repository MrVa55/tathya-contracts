// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LLMReputation is ERC20, Ownable {
    // Remove the soulbound token override completely
    
    struct Fact {
        string category1;
        string value1;
        string category2;
        string value2;
        uint256 totalStaked;      // Total amount staked on this fact
        mapping(address => uint256) stakes;  // Individual stakes per LLM
        bool exists;
    }

    // Mapping from fact hash to Fact
    mapping(bytes32 => Fact) public facts;
    // Array to track all facts
    bytes32[] public allFactHashes;
    
    // Minimum stake required to submit a fact
    uint256 public constant MINIMUM_STAKE = 100 * 10**18; // 100 tokens

    event FactStaked(
        bytes32 indexed factHash,
        string category1,
        string value1,
        string category2,
        string value2,
        address indexed staker,
        uint256 amount
    );
    
    event DirectContradiction(
        bytes32 indexed fact1Hash,
        bytes32 indexed fact2Hash,
        uint256 impactAmount
    );

    event SupportingRelationship(
        bytes32 indexed fact1Hash,
        bytes32 indexed fact2Hash,
        uint256 supportAmount
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
        // Use the standard ERC20 transfer method
        transfer(address(this), stakeAmount);

        // If new fact, initialize and add to array
        if (!facts[factHash].exists) {
            facts[factHash].category1 = category1;
            facts[factHash].value1 = value1;
            facts[factHash].category2 = category2;
            facts[factHash].value2 = value2;
            facts[factHash].exists = true;
            allFactHashes.push(factHash);
        }

        // Update fact stakes
        facts[factHash].totalStaked += stakeAmount;
        facts[factHash].stakes[msg.sender] += stakeAmount;

        emit FactStaked(
            factHash, 
            category1, 
            value1, 
            category2, 
            value2, 
            msg.sender, 
            stakeAmount
        );

        // Evaluate relationships
        _evaluateFactRelationships(factHash, stakeAmount);
    }

    function _evaluateFactRelationships(bytes32 newFactHash, uint256 newStake) internal {
        Fact storage newFact = facts[newFactHash];
        
        // Iterate through array of facts
        for (uint256 i = 0; i < allFactHashes.length; i++) {
            bytes32 factHash = allFactHashes[i];
            if (factHash == newFactHash) continue;
            
            Fact storage existingFact = facts[factHash];
            
            // Check for direct contradictions
            if (_isDirectContradiction(newFact, existingFact)) {
                uint256 impactAmount = _calculateContradictionImpact(
                    newStake,
                    existingFact.totalStaked
                );
                
                // Reduce stakes proportionally for both facts
                _applyContradictionPenalty(newFactHash, factHash, impactAmount);
                
                emit DirectContradiction(newFactHash, factHash, impactAmount);
            } 
            // Check for supporting relationship
            else if (_isSupporting(newFact, existingFact)) {
                uint256 supportAmount = _calculateSupportBonus(
                    newStake,
                    existingFact.totalStaked
                );
                
                // Increase stakes for both facts
                _applySupportBonus(newFactHash, factHash, supportAmount);
                
                emit SupportingRelationship(newFactHash, factHash, supportAmount);
            }
        }
    }

    function _isDirectContradiction(
        Fact storage fact1,
        Fact storage fact2
    ) internal view returns (bool) {
        // Direct contradiction if same categories and:
        // - same value1 but different value2, or
        // - same value2 but different value1
        return (
            (keccak256(abi.encodePacked(fact1.value1)) == keccak256(abi.encodePacked(fact2.value1)) &&
             keccak256(abi.encodePacked(fact1.value2)) != keccak256(abi.encodePacked(fact2.value2))) ||
            (keccak256(abi.encodePacked(fact1.value2)) == keccak256(abi.encodePacked(fact2.value2)) &&
             keccak256(abi.encodePacked(fact1.value1)) != keccak256(abi.encodePacked(fact2.value1)))
        );
    }

    function _isSupporting(
        Fact storage fact1,
        Fact storage fact2
    ) internal view returns (bool) {
        // Facts support each other if they share the same values
        return (
            keccak256(abi.encodePacked(fact1.value1, fact1.value2)) ==
            keccak256(abi.encodePacked(fact2.value1, fact2.value2))
        );
    }

    function _calculateContradictionImpact(
        uint256 newStake,
        uint256 existingStake
    ) internal pure returns (uint256) {
        // Impact is proportional to the geometric mean of stakes
        return sqrt(newStake * existingStake) / 2;
    }

    function _calculateSupportBonus(
        uint256 newStake,
        uint256 existingStake
    ) internal pure returns (uint256) {
        // Bonus is proportional to the geometric mean of stakes
        return sqrt(newStake * existingStake) / 4;
    }

    function _applyContradictionPenalty(
        bytes32 fact1Hash,
        bytes32 fact2Hash,
        uint256 impactAmount
    ) internal {
        // Reduce stakes proportionally
        facts[fact1Hash].totalStaked -= impactAmount;
        facts[fact2Hash].totalStaked -= impactAmount;
    }

    function _applySupportBonus(
        bytes32 fact1Hash,
        bytes32 fact2Hash,
        uint256 supportAmount
    ) internal {
        // Increase stakes
        facts[fact1Hash].totalStaked += supportAmount;
        facts[fact2Hash].totalStaked += supportAmount;
    }

    function getFactTrust(
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2
    ) external view returns (
        uint256 trustScore,
        uint256 totalStaked,
        uint256 supportCount,
        uint256 contradictionCount
    ) {
        bytes32 factHash = createFactHash(category1, value1, category2, value2);
        Fact storage fact = facts[factHash];
        
        // Base trust score is derived from total staked amount
        trustScore = fact.totalStaked;
        
        // Count direct supports and contradictions
        uint256 supportingCount = 0;
        uint256 contradictions = 0;
        
        // Iterate through array
        for (uint256 i = 0; i < allFactHashes.length; i++) {
            bytes32 otherHash = allFactHashes[i];
            if (otherHash == factHash) continue;
            
            Fact storage otherFact = facts[otherHash];
            
            if (_isDirectContradiction(fact, otherFact)) {
                contradictions++;
            } else if (_isSupporting(fact, otherFact)) {
                supportingCount++;
            }
        }
        
        return (
            trustScore,
            fact.totalStaked,
            supportingCount,
            contradictions
        );
    }

    // Helper function to calculate square root
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // Add function to get fact details
    function getFactDetails(bytes32 factHash) external view returns (
        string memory category1,
        string memory value1,
        string memory category2,
        string memory value2,
        uint256 totalStaked
    ) {
        Fact storage fact = facts[factHash];
        return (
            fact.category1,
            fact.value1,
            fact.category2,
            fact.value2,
            fact.totalStaked
        );
    }

    function getStake(bytes32 factHash, address staker) external view returns (uint256) {
        return facts[factHash].stakes[staker];
    }
}