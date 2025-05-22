import pytest
from fact_matrix import FactDatabase, Fact

@pytest.fixture
def db():
    """Create a fresh database for each test"""
    return FactDatabase()

@pytest.fixture
def populated_db():
    """Create a database with some initial facts"""
    db = FactDatabase()
    
    # Add some initial facts from our Einstein puzzle
    db.add_fact(Fact("Name", "Alex", "House", "Blue", 90))
    db.add_fact(Fact("House", "Blue", "Job", "Doctor", 80))
    db.add_fact(Fact("Job", "Doctor", "Drink", "Coffee", 70))
    db.add_fact(Fact("Name", "Brooke", "Job", "Teacher", 85))
    db.add_fact(Fact("House", "Red", "Job", "Teacher", 75))
    
    return db

def test_direct_contradiction(populated_db):
    """Test that direct contradictions are detected"""
    # This should contradict "Alex lives in Blue house"
    relationships = populated_db.analyze_fact_relationships("Name", "Brooke", "House", "Blue")
    assert len(relationships["direct_contradictions"]) > 0

def test_supporting_path(populated_db):
    """Test that supporting paths are found"""
    # Should find support for "Alex is a Doctor" through "Blue house"
    relationships = populated_db.analyze_fact_relationships("Name", "Alex", "Job", "Doctor")
    assert len(relationships["supporting_facts"]) > 0

def test_indirect_contradiction(populated_db):
    """Test that indirect contradictions are found"""
    # Should find that "Alex is a Teacher" contradicts through multiple paths
    relationships = populated_db.analyze_fact_relationships("Name", "Alex", "Job", "Teacher")
    assert len(relationships["indirect_contradictions"]) > 0

def test_trust_propagation(populated_db):
    """Test that trust scores properly propagate"""
    trust = populated_db.get_fact_trust("Name", "Alex", "Job", "Doctor")
    # Trust should be less than both source facts due to propagation
    assert trust < 90  # Less than trust in "Alex lives in Blue house"
    assert trust < 80  # Less than trust in "Doctor lives in Blue house"

def test_multiple_paths(populated_db):
    """Test handling of multiple paths between facts"""
    # Add another path between Alex and Doctor
    populated_db.add_fact(Fact("Name", "Alex", "Drink", "Coffee", 85))
    populated_db.add_fact(Fact("Job", "Doctor", "Drink", "Coffee", 75))
    
    relationships = populated_db.analyze_fact_relationships("Name", "Alex", "Job", "Doctor")
    # Should find both paths: through House and through Drink
    assert len(relationships["supporting_facts"]) == 2

def test_empty_database(db):
    """Test behavior with empty database"""
    trust = db.get_fact_trust("Name", "Alex", "House", "Blue")
    assert trust == 50  # Should return default neutral trust 