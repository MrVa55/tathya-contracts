from typing import Tuple, Dict, List, Set
from dataclasses import dataclass
import json

@dataclass
class Fact:
    category1: str
    value1: str
    category2: str
    value2: str
    trust_score: float

class FactDatabase:
    def __init__(self):
        self.facts: Dict[Tuple[Tuple[str, str], Tuple[str, str]], Fact] = {}
        
    def add_fact(self, fact: Fact) -> None:
        key = ((fact.category1, fact.value1), (fact.category2, fact.value2))
        self.facts[key] = fact

    def get_fact_trust(self, category1: str, value1: str, category2: str, value2: str) -> float:
        """
        Calculate trust score for a new fact based on existing facts
        Returns: trust score between 0-100
        """
        new_fact_key = ((category1, value1), (category2, value2))
        
        # Check direct contradictions
        direct_contradictions = []
        for existing_key, existing_fact in self.facts.items():
            if self._directly_contradicts(new_fact_key, existing_key):
                direct_contradictions.append(existing_fact)
        
        if direct_contradictions:
            # Reduce trust based on strength of contradicting facts
            contradiction_impact = max(fact.trust_score for fact in direct_contradictions)
            return max(0, 100 - contradiction_impact)
        
        # Check supporting facts through inference
        supporting_paths = self._find_supporting_paths(new_fact_key)
        if supporting_paths:
            # Calculate trust based on supporting paths
            max_support = 0
            for path in supporting_paths:
                path_trust = self._calculate_path_trust(path)
                max_support = max(max_support, path_trust)
            return max_support
        
        return 50  # Default neutral trust if no contradictions or support

    def analyze_fact_relationships(self, category1: str, value1: str, category2: str, value2: str) -> Dict:
        """
        Analyze how a new fact relates to existing facts
        Returns: Dict of contradictions and supporting facts with their trust scores
        """
        new_fact_key = ((category1, value1), (category2, value2))
        
        result = {
            "direct_contradictions": [],
            "supporting_facts": [],
            "indirect_contradictions": []
        }
        
        # Find direct contradictions
        for existing_key, existing_fact in self.facts.items():
            if self._directly_contradicts(new_fact_key, existing_key):
                result["direct_contradictions"].append({
                    "fact": existing_fact,
                    "trust": existing_fact.trust_score
                })
        
        # Find supporting paths
        supporting_paths = self._find_supporting_paths(new_fact_key)
        for path in supporting_paths:
            result["supporting_facts"].append({
                "path": path,
                "trust": self._calculate_path_trust(path)
            })
        
        # Find indirect contradictions through inference
        indirect_contradictions = self._find_indirect_contradictions(new_fact_key)
        for contradiction in indirect_contradictions:
            result["indirect_contradictions"].append({
                "path": contradiction,
                "trust": self._calculate_contradiction_impact(contradiction)
            })
        
        return result

    def _directly_contradicts(self, fact1_key: Tuple, fact2_key: Tuple) -> bool:
        """Check if two facts directly contradict (same category, different values)"""
        (cat1_a, val1_a), (cat2_a, val2_a) = fact1_key
        (cat1_b, val1_b), (cat2_b, val2_b) = fact2_key
        
        if cat1_a == cat1_b and cat2_a == cat2_b:
            return (val1_a == val1_b and val2_a != val2_b) or \
                   (val2_a == val2_b and val1_a != val1_b)
        return False

    def _calculate_path_trust(self, path: List[Fact]) -> float:
        """Calculate trust score for a path of facts"""
        if not path:
            return 0
        
        trust = path[0].trust_score
        for i in range(1, len(path)):
            # Dynamic decay based on trust of connected facts
            decay = (path[i].trust_score * trust) / 10000
            trust = min(trust, path[i].trust_score) * decay
            
        return trust

    def _find_supporting_paths(self, fact_key: Tuple) -> List[List[Fact]]:
        """Find all paths of facts that support the given fact"""
        (cat1, val1), (cat2, val2) = fact_key
        visited = set()
        paths = []
        seen_paths = set()  # To track unique paths
        
        def explore_path(current_val: str, current_cat: str, target_val: str, 
                        target_cat: str, current_path: List[Fact], depth: int):
            if depth > 3:  # Limit path length
                return
                
            # Find facts that connect to current value
            for key, fact in self.facts.items():
                if key in visited:
                    continue
                    
                # Check if this fact connects to our current position
                connects_to_current = False
                next_val = None
                next_cat = None
                
                if fact.category1 == current_cat and fact.value1 == current_val:
                    connects_to_current = True
                    next_val = fact.value2
                    next_cat = fact.category2
                elif fact.category2 == current_cat and fact.value2 == current_val:
                    connects_to_current = True
                    next_val = fact.value1
                    next_cat = fact.category1
                
                if connects_to_current:
                    visited.add(key)
                    new_path = current_path + [fact]
                    
                    # Check if we've reached our target
                    if next_cat == target_cat and next_val == target_val:
                        # Create a frozen set of fact keys to check for duplicates
                        path_key = frozenset((
                            ((f.category1, f.value1), (f.category2, f.value2))
                            for f in new_path
                        ))
                        if path_key not in seen_paths:
                            paths.append(new_path)
                            seen_paths.add(path_key)
                    else:
                        explore_path(next_val, next_cat, target_val, target_cat, 
                                   new_path, depth + 1)
                    visited.remove(key)
        
        # Only explore from one direction now
        explore_path(val1, cat1, val2, cat2, [], 0)
        
        return paths

    def _find_indirect_contradictions(self, fact_key: Tuple) -> List[List[Fact]]:
        """Find paths that lead to contradictions"""
        (cat1, val1), (cat2, val2) = fact_key
        contradicting_paths = []
        
        # First find all values connected to val1
        val1_connections = self._find_all_connections(cat1, val1)
        val2_connections = self._find_all_connections(cat2, val2)
        
        # Look for contradicting paths
        for connected_cat, connected_val in val1_connections:
            for path in self._find_supporting_paths(((cat1, val1), (connected_cat, connected_val))):
                if self._leads_to_contradiction(path, fact_key):
                    contradicting_paths.append(path)
                    
        for connected_cat, connected_val in val2_connections:
            for path in self._find_supporting_paths(((cat2, val2), (connected_cat, connected_val))):
                if self._leads_to_contradiction(path, fact_key):
                    contradicting_paths.append(path)
                    
        return contradicting_paths

    def _find_all_connections(self, category: str, value: str) -> Set[Tuple[str, str]]:
        """Find all category-value pairs connected to given value"""
        connections = set()
        
        for key, fact in self.facts.items():
            if fact.category1 == category and fact.value1 == value:
                connections.add((fact.category2, fact.value2))
            elif fact.category2 == category and fact.value2 == value:
                connections.add((fact.category1, fact.value1))
                
        return connections

    def _leads_to_contradiction(self, path: List[Fact], fact_key: Tuple) -> bool:
        """Check if a path leads to a contradiction with the given fact"""
        if not path:
            return False
            
        last_fact = path[-1]
        last_fact_key = ((last_fact.category1, last_fact.value1), 
                        (last_fact.category2, last_fact.value2))
        
        return self._directly_contradicts(last_fact_key, fact_key)

    def _calculate_contradiction_impact(self, path: List[Fact]) -> float:
        """Calculate the impact of a contradicting path"""
        path_trust = self._calculate_path_trust(path)
        # Contradiction impact decreases with path length
        return path_trust * (0.5 ** (len(path) - 1))

    def get_all_related_facts(self, category: str, value: str) -> List[Fact]:
        """Get all facts directly related to a category-value pair"""
        related = []
        for key, fact in self.facts.items():
            if (fact.category1 == category and fact.value1 == value) or \
               (fact.category2 == category and fact.value2 == value):
                related.append(fact)
        return related

# Example usage
if __name__ == "__main__":
    db = FactDatabase()
    
    # Add some initial facts
    db.add_fact(Fact("Name", "Alex", "House", "Blue", 90))
    db.add_fact(Fact("House", "Blue", "Job", "Doctor", 80))
    db.add_fact(Fact("Job", "Doctor", "Drink", "Coffee", 70))
    db.add_fact(Fact("Name", "Brooke", "Job", "Teacher", 85))
    db.add_fact(Fact("House", "Red", "Job", "Teacher", 75))
    
    # Test getting trust for a new fact
    trust = db.get_fact_trust("Name", "Alex", "Job", "Doctor")
    print(f"Trust in 'Alex is a Doctor': {trust}")
    
    # Analyze relationships
    relationships = db.analyze_fact_relationships("Name", "Alex", "House", "Red")
    print("\nRelationships for 'Alex lives in Red house':")
    print(json.dumps(relationships, indent=2, default=str))