# TEMPLATE STANDARD
rm(list = ls())    # rimuovo tutti gli oggetti presenti nella sessione
setwd('/home/dario/temp/iGraph') # workdir
library(igraph)
library(RColorBrewer)

# #############################################################################
# uno script per testare il package <igraph>

# uso come input files quelli che darei in pasto a CytoScape
network.file <- 'relationship.sif' # SIF file contenente il network
attribute.files <- c('count.na', 'desc.na') # NA files contenente gli attributi dei nodi
go.root.id <- c("GO:0008150", "GO:0005575", "GO:0003674") # GO ID dei nodi root per le tre ontologie

# importo il contenuto dei file in dataframes
{ # network
    network.df <- read.table(network.file, header = F, sep = "\t", col.names = c('child', 'rel', 'parent'), stringsAsFactors = F)
    network.df <- network.df[,c(1, 3, 2)]
}
{ # attributi dei nodi
    attribute.list <- list()
    for (filename in attribute.files) {
        att.name <- sub('.na', '', filename)
        attribute.list[[filename]] <- read.table(filename, header = F, sep = "\t", skip = 1, col.names = c('node', 'eq', att.name) , stringsAsFactors = F)
        attribute.list[[filename]]$eq <- NULL
    }
    attribute.df <- attribute.list[[1]]
    for (elem in seq(2, length(attribute.list))) {
        attribute.df <- merge(x = attribute.list[[elem]], y = attribute.df, by = "node")
    }
}

# creo un oggetto <graph>
g <- graph.data.frame(network.df, directed = T, vertices = attribute.df)

# visualizzo tutti gli attributi associati al grafo
# list.graph.attributes(g)
# list.vertex.attributes(g)
# list.edge.attributes(g)

# assegno pesi diversi ai tipi di relazione [ Wang et al. A new method to measure the semantic similarity of GO terms. Bioinformatics. 2007 May 15;23(10):1274-81. PMID: 17344234 ]
E(g)$weight <- ifelse(E(g)$rel == 'is_a', 0.8,
                              ifelse(E(g)$rel == 'part_of', 0.6, 1.0))
E(g)$color <- ifelse(E(g)$weight == 0.8, 'red',
                              ifelse(E(g)$weight == 0.6, 'blue', 'grey'))


# Faccio una distinzione tra i nodi "primitive" (quelli che ho selezionato) e i nodi "derived" (nodi che sono stati aggiunti per interconnettere i nodi primitivi)

# coloro i nodi "primitive" in accordo con il numero di geni target annotati
orange.pal = colorRampPalette(brewer.pal(9, 'Oranges')[3:7])(32)
primitive.nodes <- V(g)[ count > 0 ]$count
names(primitive.nodes) <- V(g)[ count > 0 ]$name
V(g)[name %in% names(primitive.nodes)]$color <- as.character(cut(primitive.nodes, breaks=32, labels=orange.pal))


grey.pal = colorRampPalette(brewer.pal(9, 'Greys')[1:3])(256)
V(g)[!(name %in% names(primitive.nodes))]$color <- grey.pal[1]
# derived.nodes <- V(g)[ count <= 0 ]$count
# names(derived.nodes) <- V(g)[ count <= 0 ]$name

# aspetto dei nodi
V(g)$shape <- 'circle' # forma dei nodi
V(g)$size <- 3 # larghezza
V(g)$size2 <- 4 # altezza
V(g)$label <- V(g)$count # etichette dei nodi
V(g)$label.cex <- 0.8



# layout del grafo
# g <- set.graph.attribute(g, 'layout', layout.reingold.tilford(g, root=V(g)[name %in% go.root.id])) # ad albero; root => id of the root vertex
# g <- set.graph.attribute(g, 'layout', layout.kamada.kawai(g, kkconst=vcount(g)**2, inittemp=10, sigma=vcount(g)/4 ))

g <- set.graph.attribute(g, 'layout',  layout.fruchterman.reingold.grid(g))


# par.default <- par();dev.off() # backup dei valori di default di par

# visualizzazione del grafo
postscript(file='igraph.ps', title='Ontology Graph')
plot(g, vertex.label.family = 'Helvetica', edge.arrow.size=0.25)
dev.off()

# #############################################################################
# SESSION BACKUP
# load(file = '/home/dario/temp/iGraph/LastSession.RData')
# save.image(file = '/home/dario/temp/iGraph/LastSession.RData')