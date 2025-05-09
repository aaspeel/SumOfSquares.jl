######################
# Ideal certificates #
######################

abstract type AbstractIdealCertificate <: AbstractCertificate end

struct _NonZero <: Number end
Base.iszero(::_NonZero) = false
Base.convert(::Type{_NonZero}, ::Number) = _NonZero()
Base.:*(a::_NonZero, ::Number) = a
Base.:*(::Number, a::_NonZero) = a
Base.:*(::_NonZero, a::_NonZero) = a
Base.:+(a::_NonZero, ::Number) = a
Base.:+(::Number, a::_NonZero) = a
Base.:+(::_NonZero, a::_NonZero) = a

function _combine_with_gram(
    basis::MB.SubBasis{B,M},
    gram_bases::AbstractVector{<:SA.ExplicitBasis},
    weights,
) where {B,M}
    p = zero(_NonZero, MB.algebra(MB.FullBasis{B,M}()))
    cache = zero(_NonZero, MB.algebra(MB.FullBasis{B,M}()))
    for mono in basis
        MA.operate!(
            SA.UnsafeAddMul(*),
            p,
            _term_constant_monomial(_NonZero(), mono),
            MB.algebra_element(mono),
        )
    end
    for (gram, weight) in zip(gram_bases, weights)
        MA.operate_to!(
            cache,
            +,
            GramMatrix{_NonZero}((_, _) -> _NonZero(), gram),
        )
        MA.operate!(SA.UnsafeAddMul(*), p, cache, weight)
    end
    MA.operate!(SA.canonical, SA.coeffs(p))
    return MB.SubBasis{B}(keys(SA.coeffs(p)))
end

function _reduce_with_domain(basis::MB.SubBasis, zero_basis, ::FullSpace)
    return MB.explicit_basis_covering(zero_basis, basis)
end

function _reduce_with_domain(basis, zero_basis, domain)
    return __reduce_with_domain(basis, zero_basis, domain)
end

function __reduce_with_domain(_, _, _)
    return error("Only Monomial basis support with an equalities in domain")
end
function __reduce_with_domain(
    basis::MB.SubBasis{MB.Monomial},
    ::MB.FullBasis{MB.Monomial},
    domain,
)
    I = ideal(domain)
    # set of standard monomials that are hit
    standard = Set{eltype(basis.monomials)}()
    for mono in basis.monomials
        r = rem(mono, I)
        union!(standard, MP.monomials(r))
    end
    return MB.QuotientBasis(
        MB.SubBasis{MB.Monomial}(MP.monomial_vector(collect(standard))),
        I,
    )
end

function zero_basis(
    cert::AbstractIdealCertificate,
    basis,
    domain,
    gram_bases,
    weights,
)
    return _reduce_with_domain(
        _combine_with_gram(basis, gram_bases, weights),
        _zero_basis(cert),
        domain,
    )
end

abstract type SimpleIdealCertificate{C,G,Z} <: AbstractIdealCertificate end

reduced_polynomial(::SimpleIdealCertificate, poly, domain) = poly

cone(certificate::SimpleIdealCertificate) = certificate.cone
function SumOfSquares.matrix_cone_type(
    ::Type{<:SimpleIdealCertificate{CT}},
) where {CT}
    return SumOfSquares.matrix_cone_type(CT)
end

function MA.promote_operation(
    ::typeof(gram_basis),
    ::Type{<:SimpleIdealCertificate{C,G}},
) where {C,G}
    return MB.explicit_basis_type(G)
end

"""
    struct MaxDegree{C<:SumOfSquares.SOSLikeCone,G<:SA.AbstractBasis,Z<:SA.AbstractBasis} <:
        SimpleIdealCertificate{C,G,Z}
        cone::C
        gram_basis::G
        zero_basis::Z
        maxdegree::Int
    end

The `MaxDegree` certificate ensures the nonnegativity of `p(x)` for all `x` such that
`h_i(x) = 0` by exhibiting a Sum-of-Squares polynomials `σ(x)`
such that `p(x) - σ(x)` is guaranteed to be zero for all `x`
such that `h_i(x) = 0`.
The polynomial `σ(x)` is search over `cone` with a basis of type `basis` such that
the degree of `σ(x)` does not exceed `maxdegree`.
"""
struct MaxDegree{
    C<:SumOfSquares.SOSLikeCone,
    G<:SA.AbstractBasis,
    Z<:SA.AbstractBasis,
} <: SimpleIdealCertificate{C,G,Z}
    cone::C
    gram_basis::G
    zero_basis::Z
    maxdegree::Int
end

function gram_basis(certificate::MaxDegree, poly)
    return maxdegree_gram_basis(
        certificate.gram_basis,
        MP.variables(poly),
        certificate.maxdegree,
    )
end

"""
    struct FixedBasis{C<:SumOfSquares.SOSLikeCone,G<:SA.ExplicitBasis,Z<:SA.AbstractBasis} <:
        SimpleIdealCertificate{C,G,Z}
        cone::C
        gram_basis::G
        zero_basis::Z
    end

The `FixedBasis` certificate ensures the nonnegativity of `p(x)` for all `x` such that
`h_i(x) = 0` by exhibiting a Sum-of-Squares polynomials `σ(x)`
such that `p(x) - σ(x)` is guaranteed to be zero for all `x`
such that `h_i(x) = 0`.
The polynomial `σ(x)` is search over `cone` with basis `basis`.
"""
struct FixedBasis{
    C<:SumOfSquares.SOSLikeCone,
    G<:SA.ExplicitBasis,
    Z<:SA.AbstractBasis,
} <: SimpleIdealCertificate{C,G,Z}
    cone::C
    gram_basis::G
    zero_basis::Z
end

function gram_basis(certificate::FixedBasis, _)
    return certificate.gram_basis
end

function MA.promote_operation(
    ::typeof(gram_basis),
    ::Type{<:FixedBasis{C,G}},
) where {C,G}
    return G
end

"""
    struct Newton{
        C<:SumOfSquares.SOSLikeCone,
        G<:SA.AbstractBasis,
        Z<:SA.AbstractBasis,
        N<:AbstractNewtonPolytopeApproximation,
    } <: SimpleIdealCertificate{C,G,Z}
        cone::C
        gram_basis::G
        zero_basis::Z
        newton::N
    end

The `Newton` certificate ensures the nonnegativity of `p(x)` for all `x` such that
`h_i(x) = 0` by exhibiting a Sum-of-Squares polynomials `σ(x)`
such that `p(x) - σ(x)` is guaranteed to be zero for all `x`
such that `h_i(x) = 0`.
The polynomial `σ(x)` is search over `cone` with a basis of type `basis`
chosen using the multipartite Newton polytope with parts `variable_groups`.
If `variable_groups = tuple()` then it falls back to the classical Newton polytope
with all variables in the same part.
"""
struct Newton{
    C<:SumOfSquares.SOSLikeCone,
    G<:SA.AbstractBasis,
    Z<:SA.AbstractBasis,
    N<:AbstractNewtonPolytopeApproximation,
} <: SimpleIdealCertificate{C,G,Z}
    cone::C
    gram_basis::G
    zero_basis::Z
    newton::N
end

function Newton(cone, gram_basis, zero_basis, variable_groups::Tuple)
    return Newton(
        cone,
        gram_basis,
        zero_basis,
        NewtonFilter(NewtonDegreeBounds(variable_groups)),
    )
end

function gram_basis(certificate::Newton, poly)
    return half_newton_polytope(
        _algebra_element(poly),
        MP.variables(poly),
        certificate.newton,
    )
end

"""
    struct Remainder{C<:AbstractIdealCertificate} <: AbstractIdealCertificate
        gram_certificate::C
    end

The `Remainder` certificate ensures the nonnegativity of `p(x)` for all `x` such that
`h_i(x) = 0` by guaranteeing the remainder of `p(x)` modulo the ideal generated by
`⟨h_i⟩` to be nonnegative for all `x` such that `h_i(x) = 0` using the certificate
`gram_certificate`.
For instance, if `gram_certificate` is [`SumOfSquares.Certificate.Newton`](@ref),
then the certificate `Remainder(gram_certificate)` will take the remainder before
computing the Newton polytope hence might generate a much smaller Newton polytope
hence a smaller basis and smaller semidefinite program.
However, this then corresponds to a lower degree of the hierarchy which might
be insufficient to find a certificate.
"""
struct Remainder{C<:AbstractIdealCertificate} <: AbstractIdealCertificate
    gram_certificate::C
end

function _rem(coeffs, basis::MB.FullBasis{MB.Monomial}, I)
    poly = MP.polynomial(SA.values(coeffs), SA.keys(coeffs))
    r = convert(typeof(poly), rem(poly, I))
    return MB.algebra_element(MB.sparse_coefficients(r), basis)
end

function reduced_polynomial(::Remainder, a::SA.AlgebraElement, domain)
    return _rem(SA.coeffs(a), SA.basis(a), ideal(domain))
end

function gram_basis(certificate::Remainder, poly)
    return gram_basis(certificate.gram_certificate, poly)
end

function MA.promote_operation(
    ::typeof(gram_basis),
    ::Type{Remainder{C}},
) where {C}
    return MA.promote_operation(gram_basis, C)
end

cone(certificate::Remainder) = cone(certificate.gram_certificate)

function SumOfSquares.matrix_cone_type(::Type{Remainder{GCT}}) where {GCT}
    return SumOfSquares.matrix_cone_type(GCT)
end

function _quotient_basis_type(
    ::Type{B},
    ::Type{D},
) where {T,I,B<:SA.AbstractBasis{T,I},D}
    return MB.QuotientBasis{
        T,
        I,
        B,
        MA.promote_operation(SemialgebraicSets.ideal, D),
    }
end

_zero_basis(c::SimpleIdealCertificate) = c.zero_basis

function _zero_basis_type(::Type{<:SimpleIdealCertificate{C,G,Z}}) where {C,G,Z}
    return Z
end

_zero_basis(c::Remainder) = _zero_basis(c.gram_certificate)

function _zero_basis_type(::Type{Remainder{C}}) where {C}
    return _zero_basis_type(C)
end

function MA.promote_operation(
    ::typeof(zero_basis),
    C::Type{<:Union{SimpleIdealCertificate,Remainder}},
    ::Type,
    ::Type{SemialgebraicSets.FullSpace},
    ::Type,
    ::Type,
)
    return MB.explicit_basis_type(_zero_basis_type(C))
end

function MA.promote_operation(
    ::typeof(zero_basis),
    ::Type{<:Union{SimpleIdealCertificate,Remainder}},
    ::Type{B},
    ::Type{D},
    ::Type,
    ::Type,
) where {B,D}
    return _quotient_basis_type(B, D)
end
