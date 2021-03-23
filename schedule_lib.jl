using Plots
using Dates
using XLSX

mutable struct Course
    name::String
    prep_days::Day
    available::Array{Date,1}
    date::Union{Date,Nothing}
    Ndays::Day
    
    
    function Course(name::String,prep_days::Union{Day,Int64},available::Array{Date,1};Ndays::Union{Day,Int64}=1,date::Union{Date,Nothing}=nothing)
        new(name,Day(prep_days),available,date,Day(Ndays))
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
    data = data[:,1:8] # 7 premières lignes
    
    # Check data
    params = lowercase.(["Name"; "unavailability"; "Amount days"; "preparation days";
                         "oral/written"; "start date"; "final date";""])
    @assert params == lowercase.(data[1,:]) "Corrupted excel file, please use the appropriate template"
    
    # Exam period
    @assert all(isa.([data[2,6],data[2,7]],Date)) "Please provide date format in columns F and G"
    firstdate = data[2,6]
    lastdate = data[2,7]
    
    data = data[2:end,1:5]
    @assert !any(isa.(data,Missing)) "Incomplete excel table"
    courses = Vector{Course}()
    for i = 1:size(data,1)
        name = data[i,1]
        prep_days = data[i,4]
        Ndays = data[i,3]
        available = get_available(data[i,2],firstdate,lastdate)
        
        course = Course(name,prep_days,available;Ndays=Ndays)
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

function scheduleConstraints(s::Schedule)
    for c1 in s.courses
        if c1.date ≠ nothing
            for c2 in s.courses
                if c2.date ≠ nothing && c1 ≠ c2
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
            return (i,c.name)
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
    
    (course_index,course_name)=select_unassigned_variable(s)
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
