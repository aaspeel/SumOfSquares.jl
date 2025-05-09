# # Lyapunov Function Search

#md # [![](https://mybinder.org/badge_logo.svg)](@__BINDER_ROOT_URL__/generated/Systems and Control/lyapunov_function_search.ipynb)
#md # [![](https://img.shields.io/badge/show-nbviewer-579ACA.svg)](@__NBVIEWER_ROOT_URL__/generated/Systems and Control/lyapunov_function_search.ipynb)
# **Adapted from**: SOSTOOLS' SOSDEMO2 (See Section 4.2 of [SOSTOOLS User's Manual](https://github.com/oxfordcontrol/SOSTOOLS/blob/SOSTOOLS400/docs/SOSTOOLS_400.pdf))

using Test #src
using DynamicPolynomials
@polyvar x[1:3]

# We define below the vector field ``\text{d}x/\text{d}t = f``

f = [-x[1]^3 - x[1] * x[3]^2,
     -x[2] - x[1]^2 * x[2],
     -x[3] - 3x[3] / (x[3]^2 + 1) + 3x[1]^2 * x[3]]

# We need to pick an SDP solver, see [here](https://jump.dev/JuMP.jl/v1.12/installation/#Supported-solvers) for a list of the available choices.
# We use `SOSModel` instead of `Model` to be able to use the `>=` syntax for Sum-of-Squares constraints.

using SumOfSquares
using CSDP
solver = optimizer_with_attributes(CSDP.Optimizer, MOI.Silent() => true)
model = SOSModel(solver);

# We are searching for a Lyapunov function $V(x)$ with monomials $x_1^2$, $x_2^2$ and $x_3^2$.
# We first define the monomials to be used for the Lyapunov function:

monos = x.^2

# We now define the Lyapunov function as a polynomial decision variable with these monomials:

@variable(model, V, Poly(monos))

# We need to make sure that the Lyapunov function is strictly positive.
# We can do this with a constraint $V(x) \ge \epsilon (x_1^2 + x_2^2 + x_3^2)$,
# let's pick $\epsilon = 1$:

@constraint(model, V >= sum(x.^2))

# We now compute $\text{d}V/\text{d}x \cdot f$.

using LinearAlgebra # Needed for `dot`
dVdt = dot(differentiate(V, x), f)

# The denominator is $x[3]^2 + 1$ is strictly positive so the sign of `dVdt` is the
# same as the sign of its numerator.

P = dVdt.num

# Hence, we constrain this numerator to be nonnegative:

@constraint(model, P <= 0)

# The model is ready to be optimized by the solver:

JuMP.optimize!(model)

# We verify that the solver has found a feasible solution:

JuMP.primal_status(model)
@test JuMP.primal_status(model) == MOI.FEASIBLE_POINT #src

# We can now obtain this feasible solution with:

value(V)
@test iszero(remove_monomials(polynomial(value(V)), monos)) #src
