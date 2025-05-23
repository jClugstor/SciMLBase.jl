"""
$(TYPEDEF)
"""
struct EnsembleTestSolution{T, N, S} <: AbstractEnsembleSolution{T, N, S}
    u::S
    errors::Dict{Symbol, Vector{T}}
    weak_errors::Dict{Symbol, T}
    error_means::Dict{Symbol, T}
    error_medians::Dict{Symbol, T}
    elapsedTime::Float64
    converged::Bool
end
function EnsembleTestSolution(sim::AbstractEnsembleSolution{T, N}, errors, weak_errors,
        error_means, error_medians, elapsedTime,
        converged) where {T, N}
    EnsembleTestSolution{T, N, typeof(sim.u)}(sim.u, errors, weak_errors, error_means,
        error_medians, sim.elapsedTime, sim.converged)
end
function EnsembleTestSolution(u, errors, weak_errors, error_means, error_medians,
        elapsedTime, converged)
    EnsembleTestSolution(EnsembleSolution(u, elapsedTime, converged), errors, weak_errors,
        error_means, error_medians, elapsedTime, converged)
end

"""
$(TYPEDEF)
"""
struct EnsembleSolution{T, N, S} <: AbstractEnsembleSolution{T, N, S}
    u::S
    elapsedTime::Float64
    converged::Bool
    stats::Any
end
function EnsembleSolution(sim, dims::NTuple{N}, elapsedTime, converged, stats) where {N}
    EnsembleSolution{eltype(eltype(sim)), N, typeof(sim)}(
        sim, elapsedTime, converged, stats)
end
function EnsembleSolution(sim, elapsedTime, converged, stats = nothing)
    EnsembleSolution(sim, (length(sim),), elapsedTime, converged, stats)
end # Vector of some type which is not an array
function EnsembleSolution(sim::T, elapsedTime,
        converged, stats = nothing) where {T <:
                                           AbstractVector{T2}
} where {T2 <:
             Union{AbstractArray, RecursiveArrayTools.AbstractVectorOfArray}}
    EnsembleSolution{eltype(eltype(sim)), ndims(sim[1]) + 1,
        typeof(sim)}(sim,
        elapsedTime,
        converged,
        stats)
end

struct WeightedEnsembleSolution{T1 <: AbstractEnsembleSolution, T2 <: Number}
    ensol::T1
    weights::Vector{T2}
    function WeightedEnsembleSolution(ensol, weights)
        @assert length(weights) == length(ensol)
        new{typeof(ensol), eltype(weights)}(ensol, weights)
    end
end

function Base.reverse(sim::EnsembleSolution)
    EnsembleSolution(reverse(sim.u), sim.elapsedTime, sim.converged, sim.stats)
end

"""
$(TYPEDEF)

The `EnsembleSummary` type is included to help with analyzing the general summary
statistics. Two constructors are provided:

```julia
EnsembleSummary(sim; quantiles = [0.05, 0.95])
EnsembleSummary(sim, ts; quantiles = [0.05, 0.95])
```

The first produces a `(mean,var)` summary at each time step. As with the summary
statistics, this assumes that the time steps are all the same. The second produces
a `(mean,var)` summary at each time point `t` in `ts`. This requires the ability
to interpolate the solution. Quantile is used to determine the `qlow` and `qhigh`
quantiles at each timepoint. It defaults to the 5% and 95% quantiles.

## Plot Recipe

The `EnsembleSummary` comes with a plot recipe for visualizing the summary
statistics. The extra keyword arguments are:

  - `idxs`: the solution components to plot. Defaults to plotting all components.
  - `error_style`: The style for plotting the error. Defaults to `ribbon`. Other
    choices are `:bars` for error bars and `:none` for no error bars.
  - `ci_type` : Defaults to `:quantile` which has `(qlow,qhigh)` quantiles
    whose limits were determined when constructing the `EnsembleSummary`.
    Gaussian CI `1.96*(standard error of the mean)` can be set using `ci_type=:SEM`.

One useful argument is `fillalpha` which controls the transparency of the ribbon
around the mean.
"""
struct EnsembleSummary{T, N, Tt, S, S2, S3, S4, S5} <: AbstractEnsembleSolution{T, N, S}
    t::Tt
    u::S
    v::S2
    med::S3
    qlow::S4
    qhigh::S5
    num_monte::Int
    elapsedTime::Float64
    converged::Bool
end

function calculate_ensemble_errors(sim::AbstractEnsembleSolution; kwargs...)
    calculate_ensemble_errors(sim.u; elapsedTime = sim.elapsedTime,
        converged = sim.converged, kwargs...)
end

function calculate_ensemble_errors(u; elapsedTime = 0.0, converged = false,
        weak_timeseries_errors = false,
        weak_dense_errors = false)
    errors = Dict{Symbol, Vector{eltype(u[1].u[1])}}() #Should add type information
    error_means = Dict{Symbol, eltype(u[1].u[1])}()
    error_medians = Dict{Symbol, eltype(u[1].u[1])}()

    analyticvoa = u[1].u_analytic isa AbstractVectorOfArray ? true : false

    for k in keys(u[1].errors)
        errors[k] = [sol.errors[k] for sol in u]
        error_means[k] = mean(errors[k])
        error_medians[k] = median(errors[k])
    end
    # Now Calculate Weak Errors
    weak_errors = Dict{Symbol, eltype(u[1].u[1])}()
    # Final
    m_final = mean([s.u[end] for s in u])

    if analyticvoa
        m_final_analytic = mean([s.u_analytic.u[end] for s in u])
    else
        m_final_analytic = mean([s.u_analytic[end] for s in u])
    end

    res = norm(m_final - m_final_analytic)
    weak_errors[:weak_final] = res
    if weak_timeseries_errors
        if analyticvoa
            ts_weak_errors = [mean([u[j].u[i] - u[j].u_analytic.u[i] for j in 1:length(u)])
                              for i in 1:length(u[1])]
        else
            ts_weak_errors = [mean([u[j].u[i] - u[j].u_analytic[i] for j in 1:length(u)])
                              for i in 1:length(u[1])]
        end
        ts_l2_errors = [sqrt.(sum(abs2, err) / length(err)) for err in ts_weak_errors]
        l2_tmp = sqrt(sum(abs2, ts_l2_errors) / length(ts_l2_errors))
        max_tmp = maximum([maximum(abs.(err)) for err in ts_weak_errors])
        weak_errors[:weak_l2] = l2_tmp
        weak_errors[:weak_l∞] = max_tmp
    end
    if weak_dense_errors
        densetimes = collect(range(u[1].t[1], stop = u[1].t[end], length = 100))
        u_analytic = [[sol.prob.f.analytic(sol.prob.u0, sol.prob.p, densetimes[i],
                           sol.W(densetimes[i])[1])
                       for i in eachindex(densetimes)] for sol in u]

        udense = [u[j](densetimes) for j in 1:length(u)]
        dense_weak_errors = [mean([udense[j].u[i] - u_analytic[j][i] for j in 1:length(u)])
                             for i in eachindex(densetimes)]
        dense_L2_errors = [sqrt.(sum(abs2, err) / length(err)) for err in dense_weak_errors]
        L2_tmp = sqrt(sum(abs2, dense_L2_errors) / length(dense_L2_errors))
        max_tmp = maximum([maximum(abs.(err)) for err in dense_weak_errors])
        weak_errors[:weak_L2] = L2_tmp
        weak_errors[:weak_L∞] = max_tmp
    end
    return EnsembleTestSolution(u, errors, weak_errors, error_means, error_medians,
        elapsedTime, converged)
end

### Displays

function Base.summary(io::IO, A::AbstractEnsembleSolution)
    print(io, "EnsembleSolution Solution of length ", length(A.u), " with uType:\n",
        eltype(A.u))
end
function Base.show(io::IO, m::MIME"text/plain", A::AbstractEnsembleSolution)
    summary(io, A)
end

### Plot Recipes

@recipe function f(sim::AbstractEnsembleSolution;
        zcolors = sim.u isa AbstractArray ? fill(nothing, length(sim.u)) :
                  nothing,
        trajectories = eachindex(sim))
    for i in trajectories
        size(sim.u[i].u, 1) == 0 && continue
        @series begin
            legend := false
            xlims --> (-Inf, Inf)
            ylims --> (-Inf, Inf)
            zlims --> (-Inf, Inf)
            marker_z --> zcolors[i]
            sim.u[i]
        end
    end
end

@recipe function f(sim::EnsembleSummary;
        idxs = sim.u.u[1] isa AbstractArray ? eachindex(sim.u.u[1]) :
               1,
        error_style = :ribbon, ci_type = :quantile)
    if ci_type == :SEM
        if sim.u.u[1] isa AbstractArray
            u = vecarr_to_vectors(sim.u)
        else
            u = [sim.u.u]
        end
        if sim.u.u[1] isa AbstractArray
            ci_low = vecarr_to_vectors(VectorOfArray([sqrt.(sim.v.u[i] / sim.num_monte) .*
                                                      1.96 for i in 1:length(sim.v)]))
            ci_high = ci_low
        else
            ci_low = [[sqrt(sim.v.u[i] / length(sim.num_monte)) .* 1.96
                       for i in 1:length(sim.v)]]
            ci_high = ci_low
        end
    elseif ci_type == :quantile
        if sim.med.u[1] isa AbstractArray
            u = vecarr_to_vectors(sim.med)
        else
            u = [sim.med.u]
        end
        if sim.u.u[1] isa AbstractArray
            ci_low = u - vecarr_to_vectors(sim.qlow)
            ci_high = vecarr_to_vectors(sim.qhigh) - u
        else
            ci_low = [u[1] - sim.qlow.u]
            ci_high = [sim.qhigh.u - u[1]]
        end
    else
        error("ci_type choice not valid. Must be `:SEM` or `:quantile`")
    end
    for i in idxs
        @series begin
            legend --> false
            linewidth --> 3
            fillalpha --> 0.2
            if error_style == :ribbon
                ribbon --> (ci_low[i], ci_high[i])
            elseif error_style == :bars
                yerror --> (ci_low[i], ci_high[i])
            elseif error_style == :none
                nothing
            else
                error("error_style not recognized")
            end
            sim.t, u[i]
        end
    end
end

function (sol::AbstractEnsembleSolution)(args...; kwargs...)
    [s(args...; kwargs...) for s in sol]
end

Base.@propagate_inbounds function Base.getindex(sol::WeightedEnsembleSolution, S)
    return [sum(stack(sol.weights .* sol.ensol[:, S]), dims = 2)]
end
