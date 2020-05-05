function __solve end
function __init end
function solve! end

NO_TSPAN_PROBS = Union{AbstractLinearProblem, AbstractNonlinearProblem,
                       AbstractQuadratureProblem,
                       AbstractSteadyStateProblem,AbstractJumpProblem}

function init_call(_prob,args...;kwargs...)
  if :kwargs ∈ propertynames(_prob)
    __init(_prob,args...;_prob.kwargs...,kwargs...)
  else
    __init(_prob,args...;kwargs...)
  end
end

function init(prob::DEProblem,args...;kwargs...)
  _prob = get_concrete_problem(prob,kwargs)
  if haskey(kwargs,:alg) && (isempty(args) || args[1] === nothing)
    alg = kwargs[:alg]
    isadaptive(alg) &&
    !(typeof(prob) <: NO_TSPAN_PROBS) &&
    adaptive_warn(_prob.u0,_prob.tspan)
    init_call(_prob,alg,args...;kwargs...)
  elseif !isempty(args) && typeof(args[1]) <: DEAlgorithm
    alg = args[1]
    isadaptive(alg) &&
    !(typeof(prob) <: NO_TSPAN_PROBS) &&
    adaptive_warn(_prob.u0,_prob.tspan)
    init_call(_prob,args...;kwargs...)
  else
    init_call(_prob,args...;kwargs...)
  end
end

function solve_call(_prob,args...;merge_callbacks = true, kwargs...)
  if :kwargs ∈ propertynames(_prob)
    if merge_callbacks && haskey(_prob.kwargs,:callback) && haskey(kwargs, :callback)
      kwargs_temp = NamedTuple{Base.diff_names(Base._nt_names(
      values(kwargs)), (:callback,))}(values(kwargs))
      callbacks = NamedTuple{(:callback,)}( [DiffEqBase.CallbackSet(_prob.kwargs[:callback], values(kwargs).callback )] )
      kwargs = merge(kwargs_temp, callbacks)
    end
    kwargs = merge(values(_prob.kwargs), kwargs)
  end

  logger = get(kwargs, :progress, false) ? default_logger(Logging.current_logger()) : nothing
  maybe_with_logger(logger) do
    __solve(_prob,args...; kwargs...)
  end
end

function solve(prob::DEProblem,args...;kwargs...)
  _prob = get_concrete_problem(prob,kwargs)
  if haskey(kwargs,:alg) && (isempty(args) || args[1] === nothing)
    alg = kwargs[:alg]
    isadaptive(alg) &&
    !(typeof(prob) <: NO_TSPAN_PROBS) &&
    adaptive_warn(_prob.u0,_prob.tspan)
    solve_call(_prob,alg,args...;kwargs...)
  elseif !isempty(args) && typeof(args[1]) <: DEAlgorithm
    alg = args[1]
    isadaptive(alg) &&
    !(typeof(prob) <: NO_TSPAN_PROBS) &&
    adaptive_warn(_prob.u0,_prob.tspan)
    solve_call(_prob,args...;kwargs...)
  elseif isempty(args) # Default algorithm handling
    !(typeof(prob) <: NO_TSPAN_PROBS) &&
    adaptive_warn(_prob.u0,_prob.tspan)
    solve_call(_prob,args...;kwargs...)
  else
    solve_call(_prob,args...;kwargs...)
  end
end

function solve(prob::EnsembleProblem,args...;kwargs...)
  if isempty(args)
    __solve(prob,nothing,args...;kwargs...)
  else
    __solve(prob,args...;kwargs...)
  end
end

function solve(prob::AbstractNoiseProblem,args...;kwargs...)
  __solve(prob,args...;kwargs...)
end

function get_concrete_problem(prob::AbstractJumpProblem,kwargs)
  prob
end

function get_concrete_problem(prob::AbstractSteadyStateProblem, kwargs)
  u0 = get_concrete_u0(prob, Inf, kwargs)
  u0 = promote_u0(u0, prob.p, nothing)
  remake(prob; u0 = u0)
end

function get_concrete_problem(prob::AbstractEnsembleProblem, kwargs)
  prob
end

function DiffEqBase.solve(prob::PDEProblem,alg::DiffEqBase.DEAlgorithm,args...;
                                          kwargs...)
    solve(prob.prob,alg,args...;kwargs...)
end

function discretize end

function get_concrete_problem(prob, kwargs)
  tspan = get_concrete_tspan(prob, kwargs)
  u0 = get_concrete_u0(prob, tspan[1], kwargs)
  u0 = promote_u0(u0, prob.p, tspan[1])
  tspan = promote_tspan(u0, prob.p, tspan, prob, kwargs)
  remake(prob; u0 = u0, tspan = tspan)
end

function get_concrete_problem(prob::DDEProblem, kwargs)
  tspan = get_concrete_tspan(prob, kwargs)

  u0 = get_concrete_u0(prob, tspan[1], kwargs)

  if prob.constant_lags isa Function
    constant_lags = prob.constant_lags(prob.p)
  else
    constant_lags = prob.constant_lags
  end

  u0 = promote_u0(u0, prob.p, tspan[1])
  tspan = promote_tspan(u0, prob.p, tspan, prob, kwargs)

  remake(prob; u0 = u0, tspan = tspan, constant_lags = constant_lags)
end

function get_concrete_tspan(prob, kwargs)
  if prob.tspan isa Function
    tspan = prob.tspan(prob.p)
  elseif prob.tspan === (nothing, nothing)
    if haskey(kwargs, :tspan)
      tspan = kwargs[:tspan]
    else
      error("No tspan is set in the problem or chosen in the init/solve call")
    end
  else
    tspan = prob.tspan
  end

  tspan
end

function get_concrete_u0(prob, t0, kwargs)
  if eval_u0(prob.u0)
    u0 = prob.u0(prob.p, t0)
  elseif prob.u0 === nothing
    u0 = kwargs[:u0]
  else
    u0 = prob.u0
  end

  handle_distribution_u0(u0)
end

handle_distribution_u0(_u0) = _u0
eval_u0(u0::Function) = true
eval_u0(u0) = false

"""
$(SIGNATURES)

Check whether the values of `u0` and `tspan` are appropriate for use with
adaptive integrators and emit specific warnings if they are not.
"""
function adaptive_warn(u0,tspan)
  adaptive_integer_warn(tspan)
end

"""
$(SIGNATURES)

Emit a warning about incompatibility with adaptive integers if `tspan` contains
integers.
"""
function adaptive_integer_warn(tspan)
  if eltype(tspan) <: Integer
    @warn("Integer time values are incompatible with adaptive integrators. Utilize floating point numbers instead of integers in this case, i.e. (0.0,1.0) instead of (0,1).")
  end
end

function __solve(prob::DEProblem,args...;default_set=false,second_time=false,kwargs...)
  if second_time
    error("Default algorithm choices require DifferentialEquations.jl. Please specify an algorithm or import DifferentialEquations directly.")
  elseif length(args) > 0 && !(typeof(args[1]) <: Union{Nothing,DEAlgorithm})
    error("Inappropiate solve command. The arguments do not make sense. Likely, you gave an algorithm which does not actually exist (or does not `<:DiffEqBase.DEAlgorithm`)")
  else
    __solve(prob::DEProblem,nothing,args...;default_set=false,second_time=true,kwargs...)
  end
end

################### Concrete Solve

function _concrete_solve end

function concrete_solve(prob::DiffEqBase.DEProblem,alg::DiffEqBase.DEAlgorithm,
                        u0=prob.u0,p=prob.p,args...;kwargs...)
  _concrete_solve(prob,alg,u0,p,args...;kwargs...)
end

function _concrete_solve(prob::DiffEqBase.DEProblem,alg::DiffEqBase.DEAlgorithm,
                        u0=prob.u0,p=prob.p,args...;kwargs...)
  sol = solve(remake(prob,u0=u0,p=p),alg,args...;kwargs...)
  RecursiveArrayTools.DiffEqArray(sol.u,sol.t)
end

function _concrete_solve(prob::DiffEqBase.SteadyStateProblem,alg::DiffEqBase.DEAlgorithm,
                        u0=prob.u0,p=prob.p,args...;kwargs...)
  sol = solve(remake(prob,u0=u0,p=p),alg,args...;kwargs...)
  sol.u
end

function ChainRulesCore.frule(::typeof(concrete_solve),prob,alg,u0,p,args...;
                     sensealg=nothing,kwargs...)
  _concrete_solve_forward(prob,alg,sensealg,u0,p,args...;kwargs...)
end

function ChainRulesCore.rrule(::typeof(concrete_solve),prob,alg,u0,p,args...;
                     sensealg=nothing,kwargs...)
  _concrete_solve_adjoint(prob,alg,sensealg,u0,p,args...;kwargs...)
end

ZygoteRules.@adjoint function concrete_solve(prob,alg,u0,p,args...;
                                             sensealg=nothing,kwargs...)
  _concrete_solve_adjoint(prob,alg,sensealg,u0,p,args...;kwargs...)
end

function _concrete_solve_adjoint(args...;kwargs...)
  error("No adjoint rules exist. Check that you added `using DiffEqSensitivity`")
end

function _concrete_solve_forward(args...;kwargs...)
  error("No sensitivity rules exist. Check that you added `using DiffEqSensitivity`")
end
