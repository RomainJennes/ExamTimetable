using Plots
using Dates
using XLSX
using Base.Threads

mutable struct Professor
	name::String
	available::Array{Date,1}
	parallel_exams::Int
    exams::Array{Int,1}
    
	function Professor(name::String,available::Array{Date,1},parallel_exams::Int;s::Int=0)
		name = lowercase.(name)
		name = uppercase(name[1]) * name[2:end]
        exams=zeros(Int,s)
		prof = new(name,available,parallel_exams,exams)
	end
end

mutable struct Course
    name::String
    prep_days::Day
    available::Array{Date,1}
    potential::Array{Date,1}
    date::Union{Date,Nothing}
    Ndays::Day
    promotion::String
    groups::Dict{String,Array{String,1}}
    coursegroup::Union{Nothing,String}
    oral::Bool
    prof::Union{Nothing,Professor}
    
    function Course(name::String,
            prep_days::Union{Day,Int64},
            available::Array{Date,1},
            promotion::String,
            oral::Bool;
            Ndays::Union{Day,Int64}=1,
            date::Union{Date,Nothing}=nothing,
            groups::Dict{String,Array{String,1}}=Dict{String,Array{String,1}}(),
            coursegroup::Union{Nothing,AbstractString}=nothing,
            prof::Union{Nothing,Professor}=nothing)
        
        new(name,Day(prep_days),available,copy(available),date,Day(Ndays),promotion,groups,coursegroup,oral,prof)
    end
end

mutable struct Schedule
    courses::Vector{Course}
    firstdate::Date
    lastdate::Date
    period::Array{Date,1}
    names::Vector{String}
    dates
    coursegroups::Dict{String,Array{String,1}}
    professors::Vector{Professor}

    function Schedule(courses::Vector{Course},firstdate::Date,lastdate::Date;coursegroups::Dict{String,Array{String,1}}=Dict{String,Array{Int,1}}(),professors::Vector{Professor}=Vector{Professor}())
        sort!(courses,by=x -> x.name[end-2:end])
        names = [c.name for c in courses]
        dates = firstdate:Day(1):lastdate
        schedule = new(courses,firstdate,lastdate,dates,names)
        schedule.dates = () -> unique(vcat([collect(schedule.courses[i].date:Day(1):(schedule.courses[i].date+schedule.courses[i].Ndays-Day(1))) for i in findall(x -> !isnothing(x.date),schedule.courses)]...))
        schedule.coursegroups=coursegroups
        schedule.professors=professors
        schedule
    end
end
function setDate!(s::Schedule,cindex::Int,date::Date)
    c=s.courses[cindex]
    c.date=date
    prof_index=findfirst([p.name==c.prof.name for p in s.professors])
    date_index=(date-s.firstdate).value+1
    date_index=date_index:date_index+c.Ndays.value-1
    
    prof=s.professors[prof_index]
    if c.oral
        prof.exams[date_index].+=prof.parallel_exams
    else
        prof.exams[date_index].+=1
    end
end

function prof_availabilities!(s::Schedule)
	for prof in s.professors
		courses = filter(x -> x.prof==prof,s.courses)
		for date in prof.available 
			counter = 0
			for c in courses
				if c.date==date
					if c.oral
						filter!(x->x ∉ date:Day(1):date+c.Ndays-Day(1),prof.available)
						break
					else
						counter = counter + 1
						@assert counter <= prof.parallel_exams "To much exams for this professor"
						if counter == prof.parallel_exams
							filter!(x->x≠date,prof.available)
							break
						end
					end
				end
			end
			if counter >= 1
				for c in courses
					if c.date==nothing && c.oral
						filter!(x->x≠date,c.potential)
					end
				end
			end
		end
		for course in courses
			if course.date == nothing
				filter!(x->x ∈ prof.available,course.potential)
			end
		end
	end
end

function check_prof_constraints(s::Schedule)
    for prof in s.professors
        if !all(prof.exams.<= prof.parallel_exams)
            return false
        end
    end
    return true
end

function verify_date(c1,c2,date,s_copy)
    setDate!(s_copy,findfirst([c1.name==c.name for c in s_copy.courses]),date)
    checkconstraintcouple(c1,c2) && checkconstraintcouple(c2,c1)
end

function testfull(s,cindex,d)
    s_copy=deepcopy(s)
    setDate!(s_copy,cindex,d)
    return scheduleConstraints(s_copy)
end


function fast_filtering!(s::Schedule)
    ##
end

function full_filtering!(s::Schedule)
    
    for i in 1:length(s.courses)
        c=s.courses[i]
        if c.date ==nothing
            filter!(date -> testfull(s,i,date),c.potential)
        end
    end
end


function Base.show(io::IO,s::Schedule)
    
    sleep(1e-3)
    proms = [course.promotion for course in s.courses]
    proms = unique!(proms)

    dates = s.period
    date2ind = d -> findlast(x -> x==d,dates)

    for prom in proms
    	courses = s.courses[findall(x-> x.promotion==prom,s.courses)]
    	array = zeros(length(courses),length(dates))
	    for (i,course) in enumerate(courses)
	        if course.date === nothing
	            array[i,date2ind.(course.potential)] .= 1
	        else
	            array[i,:] .= -1
	            array[i,date2ind(course.date):(date2ind(course.date+course.Ndays-Day(1)))] .= 2
	        end
	    end
	    names = [c.name for c in courses]	    
	    i = length(courses)
	    display(heatmap(array,title=prom,aspect_ratio=:equal,ylim=(0.5,i+0.5),yticks=(collect(1:i),names),
	            xticks=(collect(1:length(dates)),dates[1:end]),xrotation=-90,
	            clim=(-1,2),color=cgrad([:lightgrey, :red, :green, :yellow]),colorbar=:none,
	            grid=:all, gridalpha=1, gridlinewidth=2));
	    sleep(1e-3)

	    array = zeros(length(s.courses),length(dates))
	end
    
end


function n_available(c::Course)
    return length(c.potential)
end

function apply_arc_consistency!(s::Schedule)
    """
    Applies the arc consistency by applying constraint propagation for each possible choice of variable and value
    """
    for (i,course) in enumerate(s.courses)
        
        if course.date === nothing
            for (date_index,date) in enumerate(course.potential)
                s_test=deepcopy(s)
                setDate!(s_test,i,date)
                full_filtering!(s_test)
                if any(n_available.(s_test.courses).==0)
                    deleteat!(s.courses[i].potential,date_index)
                    apply_arc_consistency!(s)
                    return
                end
            end

        end
    end
end

function get_available(unavailable::String,firstdate::Date,lastdate::Date)
    dates = collect(firstdate:Day(1):lastdate)
    if unavailable == "0"
    	return dates
    end
    unavailable = filter(x -> !isspace(x), unavailable)
    unavailable = split(unavailable,";")
    for str in unavailable
        if !occursin("->",str)
            @assert all([isdigit(c) for c in str ]) "Unavailability format not correct"
            dates = filter(x -> Day(x) !== Day(parse(Int64,str)),dates)

        else
            nok = split(str,"->")

            for s in nok
                @assert all([isdigit(c) for c in s ]) "Unavailability format not correct"
            end

            nok = parse.(Int64,nok)
            months = unique(month.(dates))
            years = unique(year.(dates))
            @assert length(months)<3 "Exam period can't take place during more than 1 month"
            @assert length(years)==1 "Exam during multiple years not supported"
            myyear = years[1]

            if nok[2] > nok[1]
                
                if length(months) == 1
                    mymonth = months[1]
                else
                    temp = filter(x -> month(x)==months[1],dates)
                    if any([Day(d) == Day(nok[1]) for d in temp])
                        mymonth = months[1]
                    end
                    temp = filter(x -> month(x)==months[2],dates)
                    if any([Day(d) == Day(nok[1]) for d in temp])
                        mymonth = months[2]
                    end
                end
                
                
                date1 = Date(myyear,mymonth,nok[1])
                date2 = Date(myyear,mymonth,nok[2])
            else
                date1 = Date(myyear,months[1],nok[1])
                date2 = Date(myyear,months[2],nok[2])
            end
            nok = collect(date1:Day(1):date2)
            dates = filter(x -> x ∉ nok,dates)
        end
    end
    dates
end    

function import_prof(filename::String)
	@assert occursin("xlsx",filename) "Please provide an excel file"
	xf = XLSX.readxlsx(filename)
	name = XLSX.sheetnames(xf)[1]
	sheet = xf[name]
	data = sheet[:]
	data = data[:,1:6]
	params = lowercase.(["Name","unavailability","parallel exams","start date","final date","is weekend ok? (yes/no)"])
        
    @assert all(isa.([data[2,4],data[2,5]],Date)) "Please provide date format in columns D and E"
    firstdate = data[2,4]
    lastdate = data[2,5]

    sz = sum(.!isa.(data[:,1],Missing))
    data = data[2:sz,:]
    @assert !any(isa.(data[:,3],Missing)) "Incomplete excel table"

    professors = Vector{Professor}()
    for i in 1:size(data,1)
    	name = data[i,1]
    	unavailable = data[i,2]
    	if isa(unavailable,Missing)
    		unavailable = "0"
    	end
    	available = get_available(unavailable,firstdate,lastdate)
    	parallel_exams = data[i,3]

    	weekend=data[i,6]
        if weekend == "no"
            filter!(!isweekend,available)
        end


        prof = Professor(name,available,parallel_exams,s=(lastdate-firstdate).value+1)
    	push!(professors,prof)
    end
    professors
end
        

function import_excel(filename::String,professors::Vector{Professor})

	dates = Vector{Date}()
    for prof in professors
    	[push!(dates,date) for date in prof.available]
    end
    firstdate = min(dates...)
    lastdate = max(dates...)

    courses = Vector{Course}()
    coursegroups=Dict{String,Array{String,1}}()

	@assert occursin("xlsx",filename) "Please provide an excel file"
	names = XLSX.sheetnames(XLSX.readxlsx(filename))
	for name in names
		(some_courses,some_coursegroups) = import_excel_sheet(filename,professors,name)
		push!(courses,some_courses...)
		merge!(coursegroups,some_coursegroups)
	end
	Schedule(courses,firstdate,lastdate,coursegroups=coursegroups,professors=professors)
end

function import_excel_sheet(filename::String,professors::Vector{Professor},sheet::Union{String,Int64}=1)
    
    prof_names = [lowercase.(prof.name) for prof in professors]

    # Get data
    @assert occursin("xlsx",filename) "Please provide an excel file"
    xf = XLSX.readxlsx(filename)
    if typeof(sheet)==Int64
    	sheet = XLSX.sheetnames(xf)[sheet]
    end
    prom=sheet
	sh = xf[prom]
    data = sh[:]
    data = data[:,1:8] # 11 first columns, max 19 courses 
    
    # Check data
    params = lowercase.(["Name"; "Professor"; "Amount days"; "preparation days";
                         "oral/written";"promotion";"student groups";"course group"])

    @assert params == lowercase.(data[1,:]) "Corrupted excel file, please use the appropriate template"
    
    #println(data[:,1])
    #println(.!isa.(data[:,1],Missing))
    sz = sum(.!isa.(data[:,1],Missing))
    #println(sz)
    data = data[2:sz,:]
    #println(data)
    @assert !any(isa.(data[:,3:6],Missing)) "Incomplete excel table"
    courses = Vector{Course}()
    coursegroups=Dict{String,Array{String,1}}()
    for i = 1:size(data,1)
        name = data[i,1]
        prep_days = data[i,4]
        Ndays = data[i,3]
        # reg=r"^([0-9]+\s*,?\s*)+$"
        # @assert occursin(reg,string(data[i,6])) "Please specify promotion and use the correct format: prom1,prom2"
        # promotion=map(a->parse(Int,a), split(string(data[i,6]),","))
        promotion = string(data[i,6])
        
        reg=r"^([a-zA-Z0-9_]+=([a-zA-Z0-9_]+\s*,?\s*)+\s*;?\s*)*$"
        if isa(data[i,7],Missing)
            data[i,7]=""
        end
        @assert occursin(reg,data[i,7]) "Please use the correct format for groups (example: BHK=pilot,CIS;EnglishLevel=1)"
        groups=Dict{String,Array{String,1}}()
        for couple in split(data[i,7],r"\s*;\s*")
            if couple==""
                continue
            end
            r=split(couple,"=")
            groups[r[1]]=split(r[2],r"\s*,\s*")
        end
        
        if isa(data[i,8],Missing)
            coursegroup=nothing
        else
            reg=r"^([a-zA-Z0-9_]+\s*)?$"
            @assert occursin(reg,data[i,8])
            coursegroup=data[i,8]
            firstindex=findfirst([c.coursegroup==coursegroup for c in courses])
            @assert firstindex==nothing || courses[firstindex].prep_days==Day(prep_days) "Different exams in the same coursegroup should have the same number of preparation days"
            if coursegroup ∈ keys(coursegroups)
                push!(coursegroups[coursegroup],name)
            else
                coursegroups[coursegroup]=[name]
            end
        end
        
        oral=lowercase(data[i,5])
        @assert oral=="oral" || oral=="written" "Please use the correct format: oral or written"
        oral = oral=="oral"
        
        prof_name = lowercase.(data[i,2])
        @assert prof_name ∈ prof_names "Unknown professor"
        prof = professors[findfirst(prof_names.==prof_name)]

        course = Course(name,prep_days,copy(prof.available),promotion,oral;Ndays=Ndays,groups=groups,coursegroup=coursegroup,prof=prof)
        push!(courses,course)
        
    end
    (courses,coursegroups)
end


function MCV(s::Schedule)
    courses = s.courses
    available_days = Vector{}()
    for i = 1:length(courses)
        if courses[i].date === nothing
            push!(available_days,length(courses[i].potential))
        else
            push!(available_days,Inf)
        end
    end
    (value, course_index) = findmin(available_days)
    course_name = s.courses[course_index].name
    return course_index
end


function is_neighbour(course1::Course,course2::Course)
    """
    Returns true if the two courses are connected on the constraint graph i.e. if some student can follow both courses
    No student follows both if they share a keyword for which the value is different (e.g. component=land and component=navy,air)
        or if the promotion is different
    In all other cases, some combination of student properties leads him to follow both courses
    """
    common_keywords=intersect(keys(course1.groups),keys(course2.groups))
    has_common_values=[!isempty(intersect(course1.groups[k],course2.groups[k])) for k in common_keywords]
    return course1.promotion==course2.promotion && (isempty(common_keywords) || all(has_common_values))
end

function scheduleConstraints(s::Schedule)
    """
    Master function for constraints application
    Returns true if all contraints are satisfied in the current configuration
    Uses checkconstraintsingle for constraints relative to one single course (e.g. availability days ...)
    Uses checkconstraintcouple for constraints relative to two courses (e.g. not on the same day if they are neighbours ...)
    Uses checkconstraintgroups for constraints relative to a groups of courses (e.g. SE422_written and SE422_oral that must be together ...)
    """
    if !check_prof_constraints(s)
        return false
    end
    for c1 in s.courses
        
        if !checkconstraintsingle(c1)
            return false
        end
        for c2 in s.courses
            if !checkconstraintcouple(c1,c2)
                return false
            end
        end
    end
    
    return checkcontraintgroups(s)
end

function checkconstraintsingle(c1::Course)
    """
    Verifies the constraints related to a single course: all days of the exam are in the available days
    Returns true if it's ok
    """
    !(c1.date ≠ nothing && (c1.date ∉ c1.available || c1.date+c1.Ndays -Day(1) ∉ c1.available))
end


function checkconstraintcouple(c1::Course,c2::Course)
    """
    Verifies the constraints related to two courses: their can't be 2 exams at the same time and the preperation days are respected.
    If they are both oral and on multiple days, then the preparation days should only be taken between the days of passage of a student.
    We assume that the order of the students is the same for each oral exam.
    In this case, the minimal days of preparation is reached the first or the last day of the exam. We take the minimum of those two
    Constrains are directionnal so this should be called for c1,c2 and for c2,c1
    Returns true if it's ok
    """
    if c2.date ≠nothing && c1.date ≠ nothing
        tocheck= c2.date ≠ nothing && c1.date ≠ nothing && c1.name ≠ c2.name && is_neighbour(c1,c2) && c1.date>=c2.date 

        if c1.oral && c2.oral
            if c1.coursegroup==nothing || c2.coursegroup != c1.coursegroup
                checkok= min(c1.date-c2.date, c1.date+c1.Ndays-c2.date-c2.Ndays)>c1.prep_days
            else
                checkok= min(c1.date-c2.date, c1.date+c1.Ndays-c2.date-c2.Ndays)>Day(0)
            end
            
        else
            if c1.coursegroup==nothing || c2.coursegroup != c1.coursegroup
                checkok=c1.date ∉ c2.date:Day(1):(c2.date+c1.prep_days+c2.Ndays-Day(1))
            else
                checkok=c1.date ∉ c2.date:Day(1):(c2.date+c2.Ndays-Day(1))
            end
        end
        
        return !tocheck || checkok
    end
    return true
end

function checkcontraintgroups(s::Schedule)
    """
    Verifies if courses of a group (e.g. SE422_Written and SE422_oral are packed together)
    Returns true if it's ok
    """
    for (g,cs) in s.coursegroups
        dates=[]
        Ndays=Day(0)
        for c in cs
            i=findfirst([x.name==c for x in s.courses])
            
            Ndays+=s.courses[i].Ndays
            if s.courses[i].date != nothing
                push!(dates,s.courses[i].date)
            end
        end
        if length(dates)>1
            j=findfirst([x.date==max(dates...)&&x.coursegroup==g for x in s.courses])
            if max(dates...)-min(dates...)+s.courses[j].Ndays > Ndays
                return false
            end
        end
    end
    return true
end

function select_var_in_order(s::Schedule)
    i=1
    for c in s.courses
        if c.date === nothing
            return i
        end
        i+=1
    end
end

function select_val_in_order(s::Schedule,course_index::Int)
    s.courses[course_index].potential
end

function no_inference(s::Schedule)
    nothing
end

function goal_test(s::Schedule)
   all(course.date ≠ nothing for course in s.courses) && scheduleConstraints(s) 
end

function backtracking_search(s::Schedule;
                            select_unassigned_variable::Function=select_var_in_order,
                            order_domain_values::Function=select_val_in_order,
                            inference::Function=no_inference)

    inference(s)
    local result = backtrack(s,
                            select_unassigned_variable=select_unassigned_variable,
                                    order_domain_values=order_domain_values,
                                    inference=inference);
    if result == nothing
    	@warn "No solution found"
    end
    if (!(typeof(result) <: Nothing || goal_test(result)))
        error("BacktrackingSearchError: Unexpected result!")
    end
    return result;
end

function backtrack(s::Schedule;
                    select_unassigned_variable::Function=select_var_in_order,
                    order_domain_values::Function=select_val_in_order,
                    inference::Function=no_inference)
    
    if goal_test(s)
        return s
    end
    
    course_index = select_unassigned_variable(s)[1]
    for course_date in order_domain_values(s,course_index)
        s_copy=deepcopy(s)

        setDate!(s_copy,course_index,course_date)
        if scheduleConstraints(s_copy)
            inference(s_copy)
            result=backtrack(s_copy,
                            select_unassigned_variable=select_unassigned_variable,
                            order_domain_values=order_domain_values,
                            inference=inference)
            if result ≠ nothing
                return result
            end
        end
    end
    return nothing
end

function greendays(s::Schedule)
    res = 0
    for course in s.courses
        res = res + length(course.potential)
    end
    res
end

function LCV(s::Schedule,courseIndex::Int64)
    
    d = Vector{Tuple{Int64,Date}}()
    for date in s.courses[courseIndex].potential
        s_copy = deepcopy(s)
        s_copy.courses[courseIndex].date = date
        full_filtering!(s_copy)
        val = greendays(s_copy)
        push!(d,(val,date))
    end
    sort!(d, by = x -> x[1])    
    return getindex.(d,2)
end

function export_excel(s::Schedule,filename::String)
    # Creation of the Excel file
    file=filename*".xlsx";
    XLSX.openxlsx(file, mode="w") do xf #Attention : if the file is open it would be an error and if the file already exist it is erased
        # We now can write whenever we want
            # Initialisation of the data
            sheetCtr=1
            proms = [course.promotion for course in s.courses]
            courseproms = [course.promotion for course in s.courses]
            courseprof = [course.prof.name for course in s.courses]
            proms = unique!(proms)
            dates = s.period
            date2ind = d -> findlast(x -> x==d,dates)
            array=Array{String,2}(undef,length(s.courses),length(dates))
            fill!(array,"")
            names = Array{String,1}()
        
            # First do the overview
            for (i,course) in enumerate(s.courses)
                if course.date === nothing
                else
                    array[i,date2ind(course.date):(date2ind(course.date+course.Ndays-Day(1)))] .= "Exam"
                end
            end
        
        
            courseprom=[course.promotion for course in s.courses]
        
        
            array=[hcat(s.names) hcat(courseproms) hcat(courseprof) array]
            arrayv=[array[:,x] for x in 1:size(array,2)] #Need to be a column vector
        
            #First sheet : overview
            sheet = xf[1]
            XLSX.rename!(sheet, "Overview")
            XLSX.writetable!(sheet, arrayv, ["Names\\Dates","Prom", "Professor" ,collect(dates)...], anchor_cell=XLSX.CellRef("A1"))

        # We now do it for each prom
            for prom in proms
                courses = s.courses[findall(x-> x.promotion==prom,s.courses)]
                coursenames = s.names[findall(x-> x.promotion==prom,s.courses)]
                array=Array{String,2}(undef,length(courses),length(dates))
                sheetCtr+=1
                fill!(array,"")

                for (i,course) in enumerate(courses)
                     #coursenames = [coursenames course.name]
                    if course.date === nothing
                    else
                        array[i,date2ind(course.date):(date2ind(course.date+course.Ndays-Day(1)))] .= "Exam"
                    end
                
                end

                array=[hcat(coursenames) array]
                arrayv=[array[:,x] for x in 1:size(array,2)] #Need to be a column vector

                XLSX.addsheet!(xf, prom)
                XLSX.writetable!(xf[sheetCtr], arrayv, ["Names\\Dates",collect(dates)...], anchor_cell=XLSX.CellRef("A1"))
            end
    end
    println("Voici l'Excel que vous m'avez demandé !")
end

function isweekend(d::Date)
    issaturday = d->Dates.dayofweek(d) == Dates.Saturday
    issunday = d->Dates.dayofweek(d) == Dates.Sunday
    if issaturday(d) || issunday(d) == true
        return true
    else
        return false
    end
end