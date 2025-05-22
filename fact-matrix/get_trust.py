from fact_matrix import FactDatabase, Fact

def initialize_database():
    db = FactDatabase()
    
    # Initialize with some facts from Einstein puzzle
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

def get_statement_trust():
    db = initialize_database()
    
    print("\nGet trust score for a new statement")
    print("Available categories: Name, House, Job, Drink, etc.")
    
    # Get input from user
    cat1 = input("Enter first category: ").strip()
    val1 = input(f"Enter {cat1} value: ").strip()
    cat2 = input("Enter second category: ").strip()
    val2 = input(f"Enter {cat2} value: ").strip()
    
    # Calculate trust
    trust = db.get_fact_trust(cat1, val1, cat2, val2)
    
    print(f"\nTrust score for '{val1} ({cat1}) - {val2} ({cat2})': {trust:.2f}")

if __name__ == "__main__":
    get_statement_trust() 