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

# Autoassigns integrity levels to nodes.
# Needs one start node per integrity level (may not be optimal)

import networkx as nx

def applyIntegrity(graph, node, level):
	"Applies integrity to predecessors if of lower integrity"
	for pred in graph.predecessors(node):
		if nx.get_node_attributes(G,"integrity")[pred] > level:
			G.add_node(pred,integrity=level)
			if not pred in nx.get_node_attributes(G,"done"):
				applyIntegrity(graph, pred, level)
			else:
				G.add_node(pred,done=1)
	return

G=nx.read_graphml("./data.graphml")

for i in range(2):
	integrity=[]
	for n in nx.nodes(G):
		if nx.get_node_attributes(G,"integrity")[n] == i:
			integrity.append(n)
	for n in integrity:
		applyIntegrity(G,n,i)

nx.write_graphml(G,"./data.graphml")
