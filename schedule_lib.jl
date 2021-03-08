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
            for course2 in s.courses
                if course2.date === nothing
                    course2.available = filter(x -> x ∉ (course.date-course.prep_days):Day(1):course.date,course2.available)
                end
            end
        end
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
#             array[i,:] .= 1
#             array[i,course.date-course.prep_days:course.date] .= 0
            array[i,date2ind(course.date):(date2ind(course.date+course.Ndays)-1)] .= 2
        end
    end
#     mycmap = ColorGradient([RGBA(255/255,0/255,0/255),
#     RGBA(0/255,255/255,255/255),
#     RGBA(255/255,255/255,255/255)])
    
    i = length(s.courses)
    display(heatmap(array,aspect_ratio=:equal,ylim=(0.5,6.5),yticks=(collect(1:i),s.names),
            xticks=(collect(1:length(dates)),dates[1:end]),xrotation=-90,
            clim=(0,2),color=cgrad([:red, :green, :yellow]),colorbar=:none,
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
    data = data[:,1:7]
    
    # Check data
    params = lowercase.(["Name"; "unavailability"; "Amount days"; "preparation days";
                         "oral/written"; "start date"; "final date"])
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