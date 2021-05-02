 -"Dummy example.ipynb" : Some explanation and examples.
 
 - "Benchmarking.ipynb" : Performances of the code

 - "schedule_lib.jl" : Complete code for importing data, treating data, solving CSP with backtracking search, ...
 - "examparams.xlsx" : Setup file for the CSP, constraints imposed by the promotions. The "professor" field must be the name of a professor from the "professor.xlsx" file. The "student group" field is to declare some subgroups in the promotion. example : BHK=navy, BHK=pilot or lang=N/F. 

 - "professor.xlsx" : Setup file for the CSP, constraints imposed by the professors. Unavailability might be declared day by day. ex : 28;29;30. or by interval. ex : 28->30. All fields separated by a semicolon.
