using Plots
using Dates
using XLSX

mutable struct Course
    name::String
    prep_days::Day
    available::Array{Date,1}
    date::Union{Date,Nothing}
    Ndays::Day
    promotions::Array{Int,1}
    groups::Dict{String,Array{String,1}}
    
    function Course(name::String,prep_days::Union{Day,Int64},available::Array{Date,1},promotions::Array{Int,1};
            Ndays::Union{Day,Int64}=1,date::Union{Date,Nothing}=nothing, groups::Dict{String,Array{String,1}}=Dict{String,Array{String,1}}())
        new(name,Day(prep_days),available,date,Day(Ndays),promotions,groups)
    end
end

mutable struct Schedule
    courses::Vector{Course}
    firstdate::Date
    lastdate::Date
    period::Array{Date,1}
    names::Vector{String}
    dates
    function Schedule(courses::Vector{Course},firstdate::Date,lastdate::Date)
        sort!(courses,by=x -> x.name[end-2:end])
        names = [c.name for c in courses]
        dates = firstdate:Day(1):lastdate
        schedule = new(courses,firstdate,lastdate,dates,names)
        schedule.dates = () -> unique(vcat([collect(schedule.courses[i].date:Day(1):(schedule.courses[i].date+schedule.courses[i].Ndays-Day(1))) for i in findall(x -> !isnothing(x.date),schedule.courses)]...))
        schedule
    end
end




function apply_prep!(s::Schedule)
    dates = s.dates()
    for course in s.courses
        if course.date === nothing
            for date in dates
                course.available = filter(x -> x ∉ date:Day(1):(date+Day(course.prep_days)),course.available)
            end
        else
            # course.available = s.period
            for course2 in s.courses
                if course2.date === nothing
                    course2.available = filter(x -> x ∉ (course.date-course.prep_days):Day(1):course.date,course2.available)
                end
            end
        end
        if course.Ndays > Day(1) 
            check_Ndays!(course)
        end
    end 
end

function check_Ndays!(c::Course)
    if isempty(c.available)
        return
    end
    count = 1
    prev_day = c.available[1]
    for (i,day) in enumerate(c.available[2:end])

        if day == prev_day+Day(1)
            count = count+1
        elseif Day(count) < c.Ndays
            interval = (prev_day-Day(count+1)):Day(1):prev_day
            c.available = filter(x -> x ∉ interval,c.available)
            count = 1
        else
            count = 1
        end

        prev_day = day
    end
    if Day(count) < c.Ndays
        interval = prev_day-Day(count+1):Day(1):prev_day
        c.available = filter(x -> x ∉ interval,c.available)
    end
end

function Base.show(io::IO,s::Schedule)
    
    dates = s.period
    date2ind = d -> findlast(x -> x==d,dates)
    array = zeros(length(s.courses),length(dates))
    names = Array{String,1}()
    for (i,course) in enumerate(s.courses)
        if course.date === nothing
            array[i,date2ind.(course.available)] .= 1
        else
            array[i,:] .= -1
            array[i,date2ind(course.date):(date2ind(course.date+course.Ndays-Day(1)))] .= 2
        end
    end
    
    i = length(s.courses)
    display(heatmap(array,aspect_ratio=:equal,ylim=(0.5,6.5),yticks=(collect(1:i),s.names),
            xticks=(collect(1:length(dates)),dates[1:end]),xrotation=-90,
            clim=(-1,2),color=cgrad([:lightgrey, :red, :green, :yellow]),colorbar=:none,
            grid=:all, gridalpha=1, gridlinewidth=2))
    
end


function n_available(c::Course)
    return length(c.available)
end

function apply_arc_consistency!(s::Schedule)
    for (i,course) in enumerate(s.courses)
        
        if course.date === nothing
            removed = false
            for (date_index,date) in enumerate(course.available)
                
                s_test=deepcopy(s)
                s_test.courses[i].date=date
                apply_prep!(s_test)
                if any(n_available.(values(s_test.courses)).==0)
                    deleteat!(s.courses[i].available,date_index)
                    removed=true
                end
            end
            if removed
                apply_arc_consistency!(s) #because our constraints graph is fully connected 
            end
        end
    end
end


function get_available(unavailable::String,firstdate::Date,lastdate::Date)
    dates = collect(firstdate:Day(1):lastdate)
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

function import_excel(filename::String)
    
    # Get data
    @assert occursin("xlsx",filename) "Please provide an excel file"
    xf = XLSX.readxlsx(filename)
    sh = xf[XLSX.sheetnames(xf)[1]]
    data = sh[:]
    data = data[:,1:9] # 9 premières lignes
    
    # Check data
    params = lowercase.(["Name"; "unavailability"; "Amount days"; "preparation days";
                         "oral/written";"Promotions";"Groups"; "start date"; "final date"])
    @assert params == lowercase.(data[1,:]) "Corrupted excel file, please use the appropriate template"
    
    # Exam period
    @assert all(isa.([data[2,8],data[2,9]],Date)) "Please provide date format in columns H and I"
    firstdate = data[2,8]
    lastdate = data[2,9]
    
    data = data[2:end,:]
    @assert !any(isa.(data[:,1:6],Missing)) "Incomplete excel table"
    courses = Vector{Course}()
    for i = 1:size(data,1)
        name = data[i,1]
        prep_days = data[i,4]
        Ndays = data[i,3]
        available = get_available(data[i,2],firstdate,lastdate)
        reg=r"^([0-9]+,?)+$"
        @assert occursin(reg,string(data[i,6])) "Please specify promotion and use the correct format: prom1,prom2"
        promotions=map(a->parse(Int,a), split(string(data[i,6]),","))
        
        reg=r"^([a-zA-Z0-9_]+=([a-zA-Z0-9_]+,?)+;?)*$"
        if isa(data[i,7],Missing)
            data[i,7]=""
        end
        @assert occursin(reg,data[i,7]) "Please use the correct format for groups (example: BHK=pilot,CIS;EnglishLevel=1)"
        groups=Dict{String,Array{String,1}}()
        for couple in split(data[i,7],";")
            if couple==""
                continue
            end
            r=split(couple,"=")
            groups[r[1]]=split(r[2],",")
        end
        
        course = Course(name,prep_days,available,promotions;Ndays=Ndays,groups=groups)
        push!(courses,course)
    end
    Schedule(courses,firstdate,lastdate)
end;


function MCV(s::Schedule)
    courses = s.courses
    available_days = Vector{}()
    for i = 1:length(courses)
        if courses[i].date === nothing
            push!(available_days,length(courses[i].available))
        else
            push!(available_days,Inf)
        end
    end
    (value, course_index) = findmin(available_days)
    course_name = s.courses[course_index].name
    return course_index, course_name
end


function is_neighbour(course1::Course,course2::Course)
    """
    Returns true if the two courses are connected on the constraint graph i.e. some student can follow both courses
    """
    common_keywords=intersect(keys(course1.groups),keys(course2.groups))
    no_common_groups=[isempty(intersect(course1.groups[k],course2.groups[k])) for k in common_keywords]
    return !isempty(intersect(course1.promotions,course2.promotions)) && (isempty(common_keywords) || !any(no_common_groups))
end

function scheduleConstraints(s::Schedule)
    for c1 in s.courses
        if c1.date ≠ nothing
            for c2 in s.courses
                if c2.date ≠ nothing && c1 ≠ c2 && is_neighbour(c1,c2)
                    if c1.date ∈ c2.date:Day(1):(c2.date+c1.prep_days+c2.Ndays-Day(1))
                        return false
                    end
                end
            end
        end
        if c1.date ≠ nothing && (c1.date ∉ c1.available || c1.date+c1.Ndays -Day(1) ∉ c1.available)
            return false
        end
    end
    true
end

function select_var_in_order(s)
    i=1
    for c in s.courses
        if c.date === nothing
            return i
        end
        i+=1
    end
end

function select_val_in_order(s::Schedule,course_index::Int)
    s.courses[course_index].available
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
                                    order_domain_values=select_val_in_order,
                                    inference=inference);
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
    
    course_index=select_unassigned_variable(s)
    #print(course_index)
    #println(s.courses[course_index].date)
    for course_date in order_domain_values(s,course_index)
        s_copy=deepcopy(s)
        s_copy.courses[course_index].date=course_date
        if scheduleConstraints(s_copy)
            inference(s_copy)
            #println(s_copy)
            result=backtrack(s_copy,select_unassigned_variable=select_unassigned_variable,order_domain_values=order_domain_values,inference=inference)
            if result ≠ nothing
                return result
            end
        end
        
    end
    return nothing
end

function MCV(s::Schedule)
    courses = s.courses
    available_days = Vector{}()
    for i = 1:length(courses)
        if courses[i].date==nothing
            push!(available_days,length(courses[i].available))
        else
            push!(available_days,Inf)
        end
    end
    (value, coord) = findmin(available_days)
    return coord
end

function greendays(s::Schedule)
    res = 0
    for course in s.courses
        res = res + length(course.available)
    end
    res
end

function LCV(s::Schedule,courseIndex::Int64)
    
    d = Vector{Tuple{Int64,Date}}()
    for date in s.courses[courseIndex].available
        s_copy = deepcopy(s)
        s_copy.courses[courseIndex].date = date
        apply_prep!(s_copy)
        val = greendays(s_copy)
        push!(d,(val,date))
    end
    sort!(d, by = x -> x[1])    
    return getindex.(d,2)
end

function writeExcel(s::Schedule,filename::String)
    dates = s.period
    date2ind = d -> findlast(x -> x==d,dates)
    array=Array{String,2}(undef,length(s.courses),length(dates))
    fill!(array,"")
    #array = zeros(length(s.courses),length(dates))
    names = Array{String,1}()
    for (i,course) in enumerate(s.courses)
        if course.date === nothing
            #array[i,date2ind.(course.available)] .= ""
        else
            #array[i,:] .= ""
            array[i,date2ind(course.date):(date2ind(course.date+course.Ndays-Day(1)))] .= "Exam"
        end
    end
    println(array)
    #arrays=string.(array)
    
    #println(arrays)
    array=[hcat(s.names) array]
    arrayv=[array[:,x] for x in 1:size(array,2)] #Need to be a column vector
    #println(dates)
    #println((array))
    #println((ar))
    println(["Names\\Dates",collect(dates)...])
    file=filename*".xlsx";
    proms=append!(string.(1:5).*"POL",string.(1:4).*"SSMW");
    XLSX.openxlsx(file, mode="w") do xf #Attention : if the file is open it would be an error and if the file already exist it is erased
        #First sheet : overview
        sheet = xf[1]    
        XLSX.rename!(sheet, "Overview")
        XLSX.writetable!(sheet, arrayv, ["Names\\Dates",collect(dates)...], anchor_cell=XLSX.CellRef("B2"))
        
        
        
        XLSX.addsheet!(xf, "Professor")
        for prom in proms
            XLSX.addsheet!(xf, prom)
        end
    end
end
