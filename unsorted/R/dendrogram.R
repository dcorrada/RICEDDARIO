require(tcltk)
require(tkrplot)
tclRequire("Tktable")

getfile = function()
	{
	name = tclvalue(tkgetOpenFile(filetypes="{{txt files} {.txt .csv}} {{All files} *}"))
	if (name=="")
		return

	filename <<- name
	values <<- as.matrix(read.table(name, header=1, sep=","))

	numRows <<- length(values[,1])
	numCols <<- length(values[1,])
	descNames <<- names(values[1,])

	updateDescArray()
	}

showData = function()
	{
	tt2 = tktoplevel()
	tkwm.title(tt2, "Classifiers")
	tkwm.geometry(tt2, "900x700+100+100")

	descTable = tkwidget(tt2, "table", variable=descriptors, rows=numRows, cols=numCols, titlerows="1", selectmode="extended", 
		colwidth=20, background="white", xscrollcommand=function(...) tkset(xscr,...), yscrollcommand=function(...) tkset(yscr,...))
	tkconfigure(descTable, multiline=0)
	xscr = tkscrollbar(tt2,orient="horizontal", command=function(...)tkxview(descTable,...))
	yscr = tkscrollbar(tt2,command=function(...)tkyview(descTable,...))

	tkgrid(descTable, yscr, sticky="nse")
	tkgrid(xscr, sticky="new")	
	}

normData = function()
	{
	if (tclvalue(normMode) == "Mean 0 - SD 1")
		{
		for (i in 1:numCols)
			{
			values[,i] <<- (values[,i]-mean(values[,i]))/(sd(values[,i]))
			}
		}
	else if (tclvalue(normMode) == "Constrain to [0,1]")
		{
		for (i in 1:numCols)
			{
			range = max(values[,i])-min(values[,i]);

			values[,i] <<- (values[,i]-min(values[,i]))/range;
			}
		}
	
	updateDescArray()		
	}

updateDescArray = function()
	{
	for (i in 0:(numCols-1))
		descriptors[[0,i]] <<- descNames[i+1];

	for (i in 1:numRows)
		for (j in 0:(numCols-1))
			{
			descriptors[[i,j]] <<- sprintf("%0.2f",values[i,j+1])
			}
	}

plotDendro = function()
	{
	if (is.null(distMatrix))
		{	
		# Empty plot
		plot(0, type="n", xlab="", ylab="", axes=FALSE);
		return;
		}
	else
		{
		plot(dendro);
		}
	}

doDendro = function()
	{
	# Update the difference matrix
	distMatrix <<- dist(values)
	dendro <<- as.dendrogram(hclust(distMatrix));
	tkrreplot(dendPlot);
	}

# Number of rows (e.g. experiments) and columns (descriptors) of the data table
numRows = 10
numCols = 5
# Names of the descriptors
descNames = matrix(nrow=1, ncol=numCols)
# Values of the descriptors
values = matrix(nrow=numRows, ncol=numCols)
# The distance matrix
distMatrix = NULL;
dendro = NULL;

# Default initialisation
for (i in 1:numCols)
	{
	descNames[1, i] = sprintf("Descriptor %0d", i)
	}
for (i in 1:numRows)
	{
	for (j in 1:numCols)
		values[i,j] = 0.0
	}

# The TCL array where we'll store the data
descriptors = tclArray()
# Convert the values array into the TCL array
updateDescArray()
filename = NULL;
normMode = tclVar("Mean 0 - SD 1")
normModes = c("Mean 0 - SD 1", "Constrain to [0,1]")

# Generate the interface
tt = tktoplevel()
tkwm.title(tt, "Dendrogram generator")
tkwm.geometry(tt, "900x600+400+100")

leftFrame = tkframe(tt)
rightFrame = tkframe(tt)

dendPlot = tkrplot(rightFrame, plotDendro, hscale=1.2, vscale=1.2)

open = tkbutton(leftFrame, text="Choose file...", command=function(){getfile()});
show = tkbutton(leftFrame, text="Show classifiers", command=showData)
norm = tkbutton(leftFrame, text="Normalize data", command=normData)
normCombo = ttkcombobox(leftFrame, values=normModes, textvariable=normMode, state="readonly");
calc = tkbutton(leftFrame, text="Generate dendrogram", command=doDendro)

tkgrid(open)
tkgrid(show)
tkgrid(norm)
tkgrid(normCombo)
tkgrid(calc)
tkpack(dendPlot)
tkgrid(leftFrame, rightFrame, padx=10, pady=10)
