# (c) Copyright 2016-2017 Hewlett Packard Enterprise Development LP
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License, version 2, as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import networkx as nx

f = open('log','r')

high_integrity=set(["system_u:system_r:kernel_t"])
medium_integrity=set(["root:sysadm_r:sysadm_t"])

integrity=[high_integrity,medium_integrity]

G=nx.MultiDiGraph()
f.readline()

line=f.readline()

count=2

while line != '':
	security=line.split()[4].split("&")

	act=security[0].split("=")[1]
	subj=security[1].split("=")[1]
	obj=security[2].split("=")[1]

	lowest_level=len(integrity)

	G.add_node(subj,integrity=lowest_level,desc=subj)
	G.add_node(obj,integrity=lowest_level,desc=obj)

	for i in range(lowest_level):
		if subj in integrity[i]:
			G.add_node(subj,integrity=i)
		if obj in integrity[i]:
			G.add_node(obj,integrity=i)

	if obj != subj:
		if act == "w" or act == "a":
			if not G.has_edge(subj,obj):
				G.add_edge(subj,obj)
			if (nx.get_node_attributes(G,"integrity")[subj] > nx.get_node_attributes(G,"integrity")[obj]) or subj in nx.get_node_attributes(G,"dirty"):
				G.add_node(obj,dirty=count)
				if not G.has_edge(subj,obj):
					G.add_edge(subj,obj,dirty=count)

		elif act == "r":
			if not G.has_edge(obj,subj):
				G.add_edge(obj,subj)
			if (nx.get_node_attributes(G,"integrity")[obj] > nx.get_node_attributes(G,"integrity")[subj]) or obj in nx.get_node_attributes(G,"dirty"):
				G.add_node(subj,dirty=count)
				if not G.has_edge(obj,subj):
					G.add_edge(subj,obj,dirty=count)

	line=f.readline()

	count=count+1

for deg in nx.degree(G):
	if nx.degree(G)[deg]==0:
		G.remove_node(deg)

nx.write_graphml(G,"./data.graphml")
