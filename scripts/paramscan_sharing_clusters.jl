### A Pluto.jl notebook ###
# v0.19.4

using Markdown
using InteractiveUtils

# ╔═╡ a8865125-d0a0-4c6a-87ac-ebb33ab42732
#begin #ADJUST NUMBER OF PROCESSES HERE FOR PARALLEL COMPUTING
#	using Distributed
#	addprocs(6)
#end

# ╔═╡ 2a47df14-6677-4253-9460-61053e707efc
@everywhere begin #INCLUDE MODEL CODE AND NECESSARY LIBRARIES

	include("./sharing_clusters_evolutionary.jl")
	using Agents, Random, Distributions, Statistics, StatsBase
	
	parameters = Dict( #ALTER THIS DICTIONARY TO DEFINE PARAMETER DISTRIBUTIONS
	    :B => collect(2.0:2.0:40.0),
		:C => collect(0.02:0.02:0.4),
		:n => [100, 250, 500],
		:u => collect(0.05:0.05:0.95),
		:rep => collect(1:20),
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
            n = 10000,
			parallel=true,
			when_model = collect(0:1000:10000)
	)

using CSV
CSV.write("sharing_clusters_data.csv", mdf)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Distributed = "8ba89e20-285c-5b6f-9357-94700520ee1b"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
"""

# ╔═╡ Cell order:
# ╠═a8865125-d0a0-4c6a-87ac-ebb33ab42732
# ╠═2a47df14-6677-4253-9460-61053e707efc
# ╠═8f34a021-d2b6-4e69-bd83-ed03b2d85b04
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
