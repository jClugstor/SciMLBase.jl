@doc doc"""

Defines a steady state ODE problem.
Documentation Page: [https://docs.sciml.ai/DiffEqDocs/stable/types/steady_state_types/](https://docs.sciml.ai/DiffEqDocs/stable/types/steady_state_types/)

## Mathematical Specification of a Steady State Problem

To define a Steady State Problem, you simply need to give the function ``f``
which defines the ODE:

```math
\frac{du}{dt} = f(u, p, t)
```

and an initial guess ``u_0`` of where `f(u, p, t) = 0`. `f` should be specified as
`f(u, p, t)` (or in-place as `f(du, u, p, t)`), and `u₀` should be an AbstractArray
(or number) whose geometry matches the desired geometry of `u`. Note that we are not limited
to numbers or vectors for `u₀`; one is allowed to provide `u₀` as arbitrary
matrices / higher dimension tensors as well.

Note that for the steady-state to be defined, we must have that `f` is autonomous,
that is `f` is independent of `t`. But the form which matches the standard ODE
solver should still be used. The steady state solvers interpret the `f` by
fixing ``t = \infty``.

## Problem Type

### Constructors

```julia
SteadyStateProblem(f::ODEFunction, u0, p = NullParameters(); kwargs...)
SteadyStateProblem{isinplace, specialize}(f, u0, p = NullParameters(); kwargs...)
```

`isinplace` optionally sets whether the function is inplace or not. This is
determined automatically, but not inferred. `specialize` optionally controls
the specialization level. See the [specialization levels section of the SciMLBase documentation](https://docs.sciml.ai/SciMLBase/stable/interfaces/Problems/#Specialization-Levels)
for more details. The default is `AutoSpecialize`.

Parameters are optional, and if not given, a `NullParameters()` singleton
will be used, which will throw nice errors if you try to index non-existent
parameters. Any extra keyword arguments are passed on to the solvers. For example,
if you set a `callback` in the problem, then that `callback` will be added in
every solve call.

Additionally, the constructor from `ODEProblem`s is provided:

```julia
SteadyStateProblem(prob::ODEProblem)
```

Parameters are optional, and if not given, a `NullParameters()` singleton
will be used, which will throw nice errors if you try to index non-existent
parameters. Any extra keyword arguments are passed on to the solvers. For example,
if you set a `callback` in the problem, then that `callback` will be added in
every solve call.

For specifying Jacobians and mass matrices, see the DiffEqFunctions page.

### Fields

* `f`: The function in the ODE.
* `u0`: The initial guess for the steady state.
* `p`: The parameters for the problem. Defaults to `NullParameters`
* `kwargs`: The keyword arguments passed onto the solves.

## Special Solution Fields

The `SteadyStateSolution` type is different from the other DiffEq solutions because
it does not have temporal information.
"""
struct SteadyStateProblem{uType, isinplace, P, F, K} <:
       AbstractSteadyStateProblem{uType, isinplace}
    """f: The function in the ODE."""
    f::F
    """The initial guess for the steady state."""
    u0::uType
    """Parameter values for the ODE function."""
    p::P
    kwargs::K
    @add_kwonly function SteadyStateProblem{iip}(f::AbstractODEFunction{iip},
            u0, p = NullParameters();
            kwargs...) where {iip}
        _u0 = prepare_initial_state(u0)
        warn_paramtype(p)
        new{typeof(_u0), isinplace(f), typeof(p), typeof(f), typeof(kwargs)}(f, _u0, p,
            kwargs)
    end

    """
    $(SIGNATURES)

    Define a steady state problem using the given function.
    `isinplace` optionally sets whether the function is inplace or not.
    This is determined automatically, but not inferred.
    """
    function SteadyStateProblem{iip}(f, u0, p = NullParameters()) where {iip}
        SteadyStateProblem(ODEFunction{iip}(f), u0, p)
    end
end

"""
$(SIGNATURES)

Define a steady state problem using an instance of
[`AbstractODEFunction`](@ref AbstractODEFunction).
"""
function SteadyStateProblem(f::AbstractODEFunction, u0, p = NullParameters(); kwargs...)
    SteadyStateProblem{isinplace(f)}(f, u0, p; kwargs...)
end

function SteadyStateProblem(f, u0, p = NullParameters(); kwargs...)
    SteadyStateProblem(ODEFunction(f), u0, p; kwargs...)
end

function ConstructionBase.constructorof(::Type{P}) where {P <: SteadyStateProblem}
    function ctor(f, u0, p, kw)
        if f isa AbstractODEFunction
            iip = isinplace(f)
        else
            iip = isinplace(f, 4)
        end
        return SteadyStateProblem{iip}(f, u0, p; kw...)
    end
end

"""
$(SIGNATURES)

Define a steady state problem from a standard ODE problem.
"""
function SteadyStateProblem(prob::AbstractODEProblem)
    SteadyStateProblem{isinplace(prob)}(prob.f, prob.u0, prob.p; prob.kwargs...)
end

SymbolicIndexingInterface.is_time_dependent(::SteadyStateProblem) = true

@doc doc"""

Holds information on what variables to alias
when solving a SteadyStateProblem. Conforms to the AbstractAliasSpecifier interface. 
    `SteadyStateAliasSpecifier(;alias_p = nothing, alias_f = nothing, alias_u0 = nothing, alias_du0 = nothing, alias_tstops = nothing, alias = nothing)`

When a keyword argument is `nothing`, the default behaviour of the solver is used.

### Keywords 
* `alias_p::Union{Bool, Nothing}`
* `alias_f::Union{Bool, Nothing}`
* `alias_u0::Union{Bool, Nothing}`: alias the u0 array. Defaults to false .
* `alias_du0::Union{Bool, Nothing}`: alias the du0 array for DAEs. Defaults to false.
* `alias_tstops::Union{Bool, Nothing}`: alias the tstops array
* `alias::Union{Bool, Nothing}`: sets all fields of the `SteadStateAliasSpecifier` to `alias`

"""
struct SteadyStateAliasSpecifier <: AbstractAliasSpecifier
    alias_p::Union{Bool, Nothing}
    alias_f::Union{Bool, Nothing}
    alias_u0::Union{Bool, Nothing}
    alias_du0::Union{Bool, Nothing}
    alias_tstops::Union{Bool, Nothing}

    function SteadyStateAliasSpecifier(;
            alias_p = nothing, alias_f = nothing, alias_u0 = nothing,
            alias_du0 = nothing, alias_tstops = nothing, alias = nothing)
        if alias == true
            new(true, true, true, true, true)
        elseif alias == false
            new(false, false, false, false, false)
        elseif isnothing(alias)
            new(alias_p, alias_f, alias_u0, alias_du0, alias_tstops)
        end
    end
end
