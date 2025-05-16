TimeStructures release notes
===================================

Version 0.7.4 (2025-05-16)
--------------------------
* Add support for `eachindex`

Version 0.7.3 (2024-06-04)
--------------------------
* Allow Dictionaries v0.4

Version 0.7.2 (2023-05-22)
--------------------------
* Migrate from SnoopPrecompile to PrecompileTools
* Add missing package names

Version 0.7.1 (2022-10-29)
--------------------------
* Extend JuMP.Containers.rowtable for `Tables.jl` support added in JuMP v1.4.0

Version 0.7.0 (2022-10-25)
--------------------------
* Major cleanup and improved test coverage
* Breaking changes:
    - Remove `SparseVarArray' in favor of `IndexedVarArray`
    - Remove custom macros and constructors in favor of exending standard JuMP macros
    - Remove support for `DataFrame` and custom `Tables.jl` interface in favor of exending upstreamed Tables support in JuMP (will be added back when ready)

Version 0.6.2 (2022-09-19)
--------------------------
* Add IndexedVarArray that checks for valid indices on insert and has improved performance

Version 0.6.1 (2022-06-29)
--------------------------
* Release under MIT License

Version 0.4.3 (2021-11-07)
--------------------------
* Support Tables interface also for variables stored in DenseAxisArray

Version 0.3.0 (2021-09-08)
--------------------------
* Slicing and selection with ':'
* Sparse variables with index names in construction
* Support Tables.jl interface for solution variables

Version 0.1.0 (2021-06-11)
--------------------------
* Initial version
* SparseArray for data and JuMP-variables with zero for non-existing indices
* Customized and fast routines for index selection based on patterns
* Support for dynamic creation of new entries in variable arrays (SparseVarArray) 

