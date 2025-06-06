# Wilcoxon.jl
# Wilcoxon rank sum (Mann-Whitney U) tests
#
# Copyright (C) 2012   Simon Kornblith
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

export MannWhitneyUTest, ExactMannWhitneyUTest, ApproximateMannWhitneyUTest

## COMMON MANN-WHITNEY U

# Automatic exact/normal selection
"""
    MannWhitneyUTest(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})

Perform a Mann-Whitney U test of the null hypothesis that the probability that an
observation drawn from the same population as `x` is greater than an observation drawn
from the same population as `y` is equal to the probability that an observation drawn
from the same population as `y` is greater than an observation drawn from the same
population as `x` against the alternative hypothesis that these probabilities are not
equal.

The Mann-Whitney U test is sometimes known as the Wilcoxon rank-sum test.

When there are no tied ranks and ≤50 samples, or tied ranks and ≤10 samples,
`MannWhitneyUTest` performs an exact Mann-Whitney U test. In all other cases,
`MannWhitneyUTest` performs an approximate Mann-Whitney U test. Behavior may be further
controlled by using [`ExactMannWhitneyUTest`](@ref) or [`ApproximateMannWhitneyUTest`](@ref)
directly.

Implements: [`pvalue`](@ref)
"""
function MannWhitneyUTest(x::AbstractVector{S}, y::AbstractVector{T}) where {S<:Real,T<:Real}
    (U, ranks, tieadj, nx, ny, median) = mwustats(x, y)
    if nx + ny <= 10 || (nx + ny <= 50 && tieadj == 0)
        ExactMannWhitneyUTest(U, ranks, tieadj, nx, ny, median)
    else
        ApproximateMannWhitneyUTest(U, ranks, tieadj, nx, ny, median)
    end
end

# Get U, ranks, and tie adjustment for Mann-Whitney U test
# U is the sum of adjusted ranks in the first sample minus the minimal sum of ranks (ie sum(1:length(x))
function mwustats(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    ranks, tieadj = tiedrank_adj([x; y])
    nx = length(x)
    ny = length(y)
    if nx <= ny
        U = sum(@view(ranks[begin:(begin + (nx-1))])) - nx*(nx+1)/2
    else
        # Sum of adjusted ranks of first and second sample sums to (nx + ny)*(nx + ny + 1)/2, hence
        # U = (nx + ny)*(nx + ny + 1)/2 - sum(ranks_y) - nx*(nx + 1)/2
        U = ny*(2 * nx + ny + 1)/2 - sum(@view(ranks[(begin + nx):end]))
    end
    return (U, ranks, tieadj, nx, ny, median(x)-median(y))
end


## EXACT MANN-WHITNEY U TEST
struct ExactMannWhitneyUTest{T<:Real} <: HypothesisTest
    U::Float64              # test statistic: Mann-Whitney-U statistic
    ranks::Vector{Float64}  # ranks
    tie_adjustment::Float64 # adjustment for ties
    nx::Int                 # number of observations
    ny::Int
    median::T               # sample median
end

"""
    ExactMannWhitneyUTest(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})

Perform an exact Mann-Whitney U test of the null hypothesis that the probability that an
observation drawn from the same population as `x` is greater than an observation drawn
from the same population as `y` is equal to the probability that an observation drawn
from the same population as `y` is greater than an observation drawn from the same
population as `x` against the alternative hypothesis that these probabilities are not
equal.

When there are no tied ranks, the exact p-value is computed using the `wilcoxcdf` and `wilcoxccdf`
functions from the `StatsFuns` package. In the presence of tied ranks, a p-value is computed by exhaustive
enumeration of permutations, which can be very slow for even moderately sized data sets.

Implements: [`pvalue`](@ref)
"""
ExactMannWhitneyUTest(x::AbstractVector{S}, y::AbstractVector{T}) where {S<:Real,T<:Real} =
    ExactMannWhitneyUTest(mwustats(x, y)...)

testname(::ExactMannWhitneyUTest) = "Exact Mann-Whitney U test"
population_param_of_interest(x::ExactMannWhitneyUTest) = ("Location parameter (pseudomedian)", 0, x.median) # parameter of interest: name, value under h0, point estimate
default_tail(test::ExactMannWhitneyUTest) = :both

function show_params(io::IO, x::ExactMannWhitneyUTest, ident)
    print(io, ident, "number of observations in each group: ")
    show(io, [x.nx, x.ny])
    println(io)
    println(io, ident, "Mann-Whitney-U statistic:             ", x.U)
    print(io, ident, "rank sums:                            ")
    show(io, [sum(@view(x.ranks[begin:(begin + (x.nx - 1))])), sum(@view(x.ranks[(begin + x.nx):end]))])
    println(io)
    println(io, ident, "adjustment for ties:                  ", x.tie_adjustment)
end

# Enumerate all possible Mann-Whitney U results for a given vector,
# determining left-and right-tailed p values
function mwuenumerate(x::ExactMannWhitneyUTest)
    # Compute sum of ranks of the smaller group
    nx = x.nx
    ny = x.ny
    if nx <= ny
        n = nx
        R = x.U + n*(n + 1)/2
    else
        n = ny
        R = ny*(2 * nx + ny + 1)/2 - x.U
    end

    # Compare with sum of ranks of all possible groups of the same size
    le = gr = tot = 0
    for comb in combinations(x.ranks, n)
        Rp = sum(comb)
        tot += 1
        le += Rp <= R
        gr += Rp >= R
    end

    # Adjust "less"/"greater" in case the first group was not the smaller one
    if nx > n
        le, gr = gr, le
    end

    (le/tot, gr/tot)
end

function StatsAPI.pvalue(x::ExactMannWhitneyUTest; tail=:both)
    check_tail(tail)

    if x.tie_adjustment == 0
        # Compute exact p-value using method from StatsFuns, which is fast but
        # cannot account for ties
        if tail == :both
            p = wilcoxcdf(x.nx, x.ny, min(x.U, x.nx * x.ny - x.U))
            min(2 * p, 1.0)
        elseif tail == :left
            wilcoxcdf(x.nx, x.ny, x.U)
        else # tail == :right
            wilcoxccdf(x.nx, x.ny, x.U - 1)
        end
    else
        # Compute exact p-value by enumerating possible ranks in the tied data
        if tail == :both
            min(1.0, 2 * minimum(mwuenumerate(x)))
        elseif tail == :left
            mwuenumerate(x)[1]
        else # tail == :right
            mwuenumerate(x)[2]
        end
    end
end

struct ApproximateMannWhitneyUTest{T<:Real} <: HypothesisTest
    U::Float64              # test statistic: Mann-Whitney-U statistic
    ranks::Vector{Float64}  # ranks
    tie_adjustment::Float64 # adjustment for ties
    nx::Int                 # number of observations
    ny::Int
    median::T               # sample median
    mu::Float64             # normal approximation: mean
    sigma::Float64          # normal approximation: std
end

## APPROXIMATE MANN-WHITNEY U TEST
"""
    ApproximateMannWhitneyUTest(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})

Perform an approximate Mann-Whitney U test of the null hypothesis that the probability that
an observation drawn from the same population as `x` is greater than an observation drawn
from the same population as `y` is equal to the probability that an observation drawn
from the same population as `y` is greater than an observation drawn from the same
population as `x` against the alternative hypothesis that these probabilities are not
equal.

The p-value is computed using a normal approximation to the distribution of the
Mann-Whitney U statistic:
```math
    \\begin{align*}
        μ & = \\frac{n_x n_y}{2}\\\\
        σ & = \\frac{n_x n_y}{12}\\left(n_x + n_y + 1 - \\frac{a}{(n_x + n_y)(n_x +
            n_y - 1)}\\right)\\\\
        a & = \\sum_{t \\in \\mathcal{T}} t^3 - t
    \\end{align*}
```
where ``\\mathcal{T}`` is the set of the counts of tied values at each tied position.

Implements: [`pvalue`](@ref)
"""
function ApproximateMannWhitneyUTest(U::Real, ranks::AbstractVector{T},
    tie_adjustment::Real, nx::Int, ny::Int, median::Real) where T<:Real
    n = nx + ny
    nxny = nx * ny
    mu = U - nxny / 2
    sigma = sqrt(nxny / 12 * (n + 1 - tie_adjustment / (n * (n - 1))))
    ApproximateMannWhitneyUTest(U, ranks, tie_adjustment, nx, ny, median, mu, sigma)
end
ApproximateMannWhitneyUTest(x::AbstractVector{S}, y::AbstractVector{T}) where {S<:Real,T<:Real} =
    ApproximateMannWhitneyUTest(mwustats(x, y)...)

testname(::ApproximateMannWhitneyUTest) = "Approximate Mann-Whitney U test"
population_param_of_interest(x::ApproximateMannWhitneyUTest) = ("Location parameter (pseudomedian)", 0, x.median) # parameter of interest: name, value under h0, point estimate
default_tail(test::ApproximateMannWhitneyUTest) = :both

function show_params(io::IO, x::ApproximateMannWhitneyUTest, ident)
    println(io, ident, "number of observations in each group: ", [x.nx, x.ny])
    println(io, ident, "Mann-Whitney-U statistic:             ", x.U)
    println(io, ident, "rank sums:                            ", [sum(@view(x.ranks[begin:(begin + (x.nx - 1))])), sum(@view(x.ranks[(begin + x.nx):end]))])
    println(io, ident, "adjustment for ties:                  ", x.tie_adjustment)
    println(io, ident, "normal approximation (μ, σ):          ", (x.mu, x.sigma))
end

function StatsAPI.pvalue(x::ApproximateMannWhitneyUTest; tail=:both)
    check_tail(tail)

    if x.mu == x.sigma == 0
        1.0
    elseif tail == :both
        p = 2 * ccdf(Normal(), abs(x.mu - 0.5 * sign(x.mu))/x.sigma)
        min(p, 1.0)
    elseif tail == :left
        cdf(Normal(), (x.mu + 0.5)/x.sigma)
    else # tail == :right
        ccdf(Normal(), (x.mu - 0.5)/x.sigma)
    end
end
