begin #ADJUST NUMBER OF PROCESSES HERE FOR PARALLEL COMPUTING
	using Distributed
	addprocs(6)
end

# ╔═╡ 2a47df14-6677-4253-9460-61053e707efc
@everywhere begin #INCLUDE MODEL CODE AND NECESSARY LIBRARIES

	using Agents, Random, Distributions, Statistics, StatsBase

    """
    Cluster agent class
    """
    mutable struct Cluster <: AbstractAgent
        id::Int64
        size::Int64
        s::Float64 #sharing norm of cluster
        total_fitness::Float64
        average_fitness::Float64
        ϕ::Float64 #probability of receiving new member
        τ::Float64 #probability of losing a member (if whole pop is in the clusters)
        #fission_prob::Float64
    end

    function sharing_groups_model(;
        N::Int64 = 20, #number of sharing clusters
        max_N::Int64 = 100, #max number of sharing clusters
        n::Int64 = 200, #population size
        r::Int64 = 1, #number of agents that join/abandon clusters
        T::Int64 = 20, #number of sub-periods in productive period
        init_size::Int64 = 10, #initial max size of clusters (binomial distribution)
        init_size_prob::Float64 = 0.5, #probability of cluster size
        B::Float64 = 20.0, #mean of surplus distribution (lognormal)
        B_var::Float64 = 0.0001, #variance of surplus distribution
        C::Float64 = 0.2, #mean of cost distribution (lognormal)
        C_var::Float64 = 0.0001, #variance of cost distribution
        α_risk::Float64 = 1001.0, #alpha (# of successes - 1) for risk distribution
        β_risk::Float64 = 1001.0, #beta (# of failures - 1) for risk distribution
        δ::Float64 = 0.1, #strength of selection
        γ::Float64 = 10.0, #steepness of sigmoid for fission probability
        σ_small::Float64 = 0.01, #variance of inherited sharing norm after fission
        σ_large::Float64 = 0.1, #prob of large mutation in sharing norm after fission
        rep::Int64 = 1, #replicate number (paramscan only)
        )

        model = ABM(
            Cluster,
            nothing,
            properties = Dict(
                :N => N,
                :max_N => max_N,
                :r => r,
                :T => T,
                :B => LogNormal(log(B), B_var),
                :C => LogNormal(log(C), C_var),
                :size_dist => Binomial(init_size, init_size_prob),
                :share_dist => Beta(1, 1),
                :risk => Beta(α_risk, β_risk),
                :δ => δ,
                :γ => γ,
                :σ_small => σ_small,
                :σ_large => σ_large,
                :n => n,
                :current_n => 0,
                :current_N => N,
                :max_cluster_size => 0,
                :mean_sharing => 0.0,
                :median_sharing => 0.0,
                :mean_cluster_size => 0.0,
                :median_cluster_size => 0.0,
                :mean_sharing_vector => Float64[], #containers for pop-level data
                :median_sharing_vector => Float64[],
                :num_clusters_vector => Int64[],
                :mean_cluster_size_vector => Float64[],
                :median_cluster_size_vector => Float64[],
                :loner_fitness => (1+δ)^(T*( α_risk/(α_risk + β_risk) )*log(B)),
                :tick => 0,
                :rep => rep,
            ),
            rng = RandomDevice(),
        )

        for a in 1:N #add initial agents
            add_agent!(
                model,
                rand(model.rng, model.size_dist),
                rand(model.rng, model.share_dist),
                0.0,
                0.0,
                0.0,
                0.0,
            )
        end

        model.current_n = sum([a.size for a in allagents(model)])

        return model

    end


    function generate_fitness!(model)

        for a in allagents(model) #iterate through all agents

            log_payoffs = zeros(a.size) #calculate payoffs on log scale for convenience

            for t in 1:model.T #iterate through every sub-period of productive period

                pool = 0
                members = Float64[]
                #calculate individual and pooled payoff for sub-period:
                for member in 1:(a.size) #iterate through every member of pool
                    u = rand(model.rng, model.risk)
                    B = rand(model.rng, model.B)
                    C = rand(model.rng, model.C)
                    toss = ( rand(model.rng) < u )
                    pool += toss ? a.s*B : 0
                    netcost = (a.size - 1)*C
                    member_payoff = toss ? (1 - a.s) * B - netcost : 1.0 - netcost
                    push!(members, member_payoff)
                end

                share = pool / a.size #give a share of resource to all members
                full_member_payoffs = clamp.(share.+members, 1, 1000)

                #calculate the average log growth rate
                log_payoffs += log.(full_member_payoffs)

            end
            #calculate fitness
            a.total_fitness = sum( (1 + model.δ).^log_payoffs )
            a.average_fitness = a.total_fitness / a.size

        end

    end


    function growth!(model)

        #fissfunc(fitness) = 1 / ( 1 + exp( -model.γ * (fitness - model.loner_fitness) ) )

        pop_fitness = sum( [a.total_fitness for a in allagents(model)] )
        #pop_fission = sum( [fissfunc(a.average_fitness) for a in allagents(model)] )

        for a in allagents(model)
            a.ϕ = a.total_fitness / pop_fitness
            a.τ = -(a.ϕ - 1.0)
            #a.fission_prob = fissfunc(a.average_fitness) / pop_fission
        end

        recruiter = sample(
            model.rng,
            allagents(model) |> collect,
            Weights( [a.ϕ for a in allagents(model)] )
        )

        if model.current_n < model.n

            recruiter.size += model.r
            model.current_n += model.r
            #rand(model.rng, Binomial(model.n, model.n_prob))

        else

            loser = sample(
                model.rng,
                allagents(model) |> collect,
                Weights( [a.τ for a in allagents(model)] )
            )

            loser.size -= model.r
            loser_size = loser.size

            recruiter.size += model.r

            if loser_size < 1

                kill_agent!(loser, model)
                model.current_N -= 1

            end

        end

    end



    function death_and_fission!(model)

        # we want to count how many groups fissioned
        # and then remove that amount of agents at random

        #we do not consider for reproduction or fission those groups that have fitness
        #below that of a loner and group size at or below 1

        fission_candidates = []
        for a in allagents(model)
            if (a.average_fitness ≤ model.loner_fitness) & (a.size > 2)
                push!(fission_candidates, a)
            end
        end

        if length(fission_candidates) > 0

            fissioned = rand(model.rng, fission_candidates)

            inh_sharing = clamp( rand(model.rng, Normal(fissioned.s, model.σ_small)), 0.0, 1.0 )

            mutated_sharing = rand(model.rng)

            new_size = floor( rand(model.rng) * fissioned.size )
            if new_size > 0

                fissioned.size -= new_size

                add_agent!(
                    model,
                    new_size,
                    rand(model.rng) < model.σ_large ? mutated_sharing : inh_sharing,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                )

                model.current_N += 1

                if model.current_N > model.max_N

                    dead = sample(
                        model.rng,
                        allagents(model) |> collect,
                        Weights( [-(a.ϕ - 1.0) for a in allagents(model)] )
                    )

                    model.current_n -= dead.size

                    model.current_N -= 1

                    kill_agent!(dead, model)

                end

            end

        end

    end



    function sharing_step!(model)
        generate_fitness!(model)
        growth!(model)
        death_and_fission!(model)

        sharings = [a.s for a in allagents(model)]
        model.mean_sharing = mean(sharings)
        model.median_sharing = median(sharings)

        sizes = [a.size for a in allagents(model)]
        model.mean_cluster_size = mean(sizes)
        model.median_cluster_size = median(sizes)
        model.max_cluster_size = maximum(sizes)

        push!(model.mean_sharing_vector, model.mean_sharing)
        push!(model.median_sharing_vector, model.median_sharing)
        push!(model.mean_cluster_size_vector, model.mean_cluster_size)
        push!(model.median_cluster_size_vector, model.median_cluster_size)
        push!(model.num_clusters_vector, model.current_N)

        model.tick += 1
    end


    parameters = Dict( #ALTER THIS DICTIONARY TO DEFINE PARAMETER DISTRIBUTIONS
        :B => collect(5.0:5:40.0),
        :C => collect(0.05:0.05:0.4),
        #:max_N => collect(20:10:100),
        :α_risk => [1.0, 501.0, 1001.0, 2001.0, 10001.0, 20001.0],
        :β_risk => [1001.0],
        :rep => collect(1:5),
    )


    mdata = [
        :current_n,
        :current_N,
        :max_cluster_size,
        :mean_sharing,
        :median_sharing,
        :mean_cluster_size,
        :median_cluster_size,
    ]

end

# ╔═╡ 8f34a021-d2b6-4e69-bd83-ed03b2d85b04
#USE THIS LINE AFTER DEFINITIONS TO BEGIN PARAMETER SCANNING
_, mdf = paramscan(
            parameters, sharing_groups_model;
            mdata=mdata,
            agent_step! = dummystep,
        	model_step! = sharing_step!,
            n = 5000,
			parallel=true,
			when_model = [5000]
	)
