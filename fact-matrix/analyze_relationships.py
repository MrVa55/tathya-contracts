from fact_matrix import FactDatabase, Fact
import json

def initialize_database():
    # Same as in get_trust.py
    db = FactDatabase()
    
    initial_facts = [
        Fact("Name", "Alex", "House", "Blue", 90),
        Fact("House", "Blue", "Job", "Doctor", 80),
        Fact("Job", "Doctor", "Drink", "Coffee", 70),
        Fact("Name", "Brooke", "Job", "Teacher", 85),
        Fact("House", "Red", "Job", "Teacher", 75),
        # Add more initial facts as needed
    ]
    
    for fact in initial_facts:
        db.add_fact(fact)
    
    return db

def analyze_statement_relationships():
    db = initialize_database()
    
    print("\nAnalyze relationships for a new statement")
    print("Available categories: Name, House, Job, Drink, etc.")
    
    # Get input from user
    cat1 = input("Enter first category: ").strip()
    val1 = input(f"Enter {cat1} value: ").strip()
    cat2 = input("Enter second category: ").strip()
    val2 = input(f"Enter {cat2} value: ").strip()
    
    # Get relationships
    relationships = db.analyze_fact_relationships(cat1, val1, cat2, val2)
    
    # Pretty print results
    print(f"\nAnalysis for '{val1} ({cat1}) - {val2} ({cat2})':")
    print("\nDirect Contradictions:")
    for contra in relationships["direct_contradictions"]:
        fact = contra["fact"]
        print(f"- {fact.value1} ({fact.category1}) - {fact.value2} ({fact.category2})")
        print(f"  Trust: {contra['trust']:.2f}")
    
    print("\nSupporting Facts:")
    for support in relationships["supporting_facts"]:
        print("\nSupporting Path:")
        for fact in support["path"]:
            print(f"- {fact.value1} ({fact.category1}) - {fact.value2} ({fact.category2})")
        print(f"  Path Trust: {support['trust']:.2f}")
    
    print("\nIndirect Contradictions:")
    for contra in relationships["indirect_contradictions"]:
        print("\nContradicting Path:")
        for fact in contra["path"]:
            print(f"- {fact.value1} ({fact.category1}) - {fact.value2} ({fact.category2})")
        print(f"  Contradiction Impact: {contra['trust']:.2f}")

if __name__ == "__main__":
    analyze_statement_relationships() 