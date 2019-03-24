# Generate a toy problem without any obvious structure in the mean, precision, or noise std.
# Important to ensure that the unit tests don't just pass for a special case by accident.
# Everything should be reasonably well conditioned.
function generate_toy_problem(rng, N, D)
    X, B, C = randn(rng, D, N), randn(rng, D, D), 0.1 * randn(rng, N, N)
    mw, Λw, Σy = randn(rng, D), B * B' + I, C * C' + I
    return X, BayesianLinearRegressor(mw, Λw), Σy
end

@testset "blr" begin
    @testset "marginals" begin
        rng, N, D, samples = MersenneTwister(123456), 11, 3, 1_000_000
        X, f, Σy = generate_toy_problem(rng, N, D)

        @test mean.(marginals(f(X, Σy))) == mean(f(X, Σy))
        @test std.(marginals(f(X, Σy))) == sqrt.(diag(cov(f(X, Σy))))
    end
    @testset "rand" begin
        rng, N, D, samples = MersenneTwister(123456), 11, 3, 10_000_000
        X, f, Σy = generate_toy_problem(rng, N, D)

        # Check deterministic properties of rand.
        @test size(rand(rng, f(X, Σy))) == (N,)
        @test size(rand(rng, f(X, Σy), samples)) == (N, samples)

        # Roughly test the statistical properties of rand.
        Y = rand(rng, f(X, Σy), samples)
        m_empirical = mean(Y; dims=2)
        Σ_empirical = (Y .- mean(Y; dims=2)) * (Y .- mean(Y; dims=2))' ./ samples
        @test mean(f(X, Σy)) ≈ m_empirical atol=1e-3 rtol=1e-3
        @test cov(f(X, Σy)) ≈ Σ_empirical atol=1e-3 rtol=1e-3
    end
    @testset "logpdf" begin
        rng, N, D = MersenneTwister(123456), 13, 7
        X, f, Σy = generate_toy_problem(rng, N, D)
        y = rand(rng, f(X, Σy))

        # Construct MvNormal using a naive but simple computation for the mean / cov.
        m, Σ = X' * f.mw, Symmetric(X' * (cholesky(f.Λw) \ X) + Σy)

        # Check that logpdf agrees between distributions and BLR.
        @test logpdf(f(X, Σy), y) ≈ logpdf(MvNormal(m, Σ), y)
    end
    @testset "posterior" begin
        @testset "low noise" begin
            rng, N, D = MersenneTwister(123456), 13, 7
            X, f, Σy = generate_toy_problem(rng, N, D)
            y = rand(rng, f(X, eps()))

            f′_low_noise = posterior(f(X, eps()), y)
            @test mean(f′_low_noise(X, eps())) ≈ y
            @test all(cov(f′_low_noise(X, eps())) .< 1_000 * eps())
        end
        @testset "repeated conditioning" begin
            rng, N, D = MersenneTwister(123456), 13, 7
            X, f, Σy = generate_toy_problem(rng, N, D)
            X′ = randn(rng, D, N)
            y = rand(rng, f(X, Σy))

            # Chop up the noise because we can't condition on noise that's correlated
            # between things.
            N1 = N - 3
            Σ1, Σ2 = Σy[1:N1, 1:N1], Σy[N1+1:end, N1+1:end]
            Σy′ = vcat(
                hcat(Σ1, zeros(N1, N - N1)),
                hcat(zeros(N - N1, N1), Σ2),
            )

            X1, X2 = X[:, 1:N1], X[:, N1+1:end]
            y1, y2 = y[1:N1], y[N1+1:end]

            f′1 = posterior(f(X1, Σ1), y1)
            f′2 = posterior(f′1(X2, Σ2), y2)
            f′ = posterior(f(X, Σy′), y)
            @test mean(f′(X′, Σy)) ≈ mean(f′2(X′, Σy))
            @test cov(f′(X′, Σy)) ≈ cov(f′2(X′, Σy))
        end
    end
end