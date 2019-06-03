require 'json'
require 'net/http'
require 'date'
require 'colorize'

$baseUrl = ENV["BASE_URL"]
$team = ENV["TEAM"]
$token = `cat ~/.flyrc | grep "team: #{$team}" -A 3 | grep -E $'value( .*)?' | awk '{print $2}'`
$limit = 10

def readableDuration(seconds)
    "%02d days, %02d hrs, %02d mins" % [seconds/86400, seconds/3600%24, seconds/60%60]
end

def readableDateTime(timestamp)
    Time.at(timestamp).strftime("%b %e, %l:%M %p")
end

def average(array)
    array.reduce(:+) / array.size
end

def median(array)
    sorted = array.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
end

def askConcourse(path)
    uri = URI("#{$baseUrl}#{path}")
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true

    req = Net::HTTP::Get.new(uri)
    req['authorization'] = "Bearer #{$token.strip}"
    res = http.request(req)

    JSON.parse(res.body)
end

def getOutputs(pipeline, jobName, outputName, builds={"max" => nil, "number" => nil })
    getFromListOfBuilds(pipeline, jobName, "outputs", "resource", outputName, builds)
end

def getInputs(pipeline, jobName, inputName, builds={"max" => nil, "number" => nil })
    getFromListOfBuilds(pipeline, jobName, "inputs", "name", inputName, builds)
end

def getFromListOfBuilds(pipeline, jobName, listKey, candidateKey, candidateValue, builds)
    # "
    versionInfos = []
    i = 0
    buildNumberPath = builds["number"] ? "/#{builds["number"]}" : ""
    buildsPath = "/api/v1/teams/#{$team}/pipelines/#{pipeline}/jobs/#{jobName}/builds#{buildNumberPath}?limit=#{$limit}"
    allBuilds = builds["number"] ? [askConcourse(buildsPath)] : askConcourse(buildsPath)
    allBuilds.each do |jobBuild|
        if builds["max"] != nil && i >= builds["max"] then
            break
        end
        jobResourcesPath = jobBuild["api_url"]
        jobResources = askConcourse("#{jobResourcesPath}/resources")
        candidate = jobResources[listKey].select{|x| x[candidateKey] == candidateValue}[0]
        print ".".light_black
        versionInfos.push(
            {
                "jobName" => jobName,
                "name" => jobBuild["name"],
                candidateValue => candidate,
                "status" => jobBuild["status"],
                "start_time" => jobBuild["start_time"]
            }
        )
        i = i+1
    end
    puts ""
    versionInfos
end

# cycle = a combination of "end" and "start" with the same commit, and a successful end
def getCycles(startInputs, endInputs)
    result = endInputs.map do |ending|
        startCandidates = startInputs.select{|x| x["shas"] != nil && (x["shas"] && ending["shas"]).length > 0 }

        if startCandidates && startCandidates.length > 0 then
            earliestStartTime = startCandidates.map{|x| x["start_time"]}.min
            startJob = startCandidates.select{|x| x["start_time"] == earliestStartTime}[0]

            duration = ending["start_time"] - startJob["start_time"]
            {
                "duration" => duration,
                "shas" => ending["shas"],
                "start" => {
                    "name" => startJob["jobName"],
                    "number" => startJob["name"],
                    "time" => startJob["start_time"]
                },
                "end" => {
                    "name" => ending["jobName"],
                    "number" => ending["name"],
                    "time" => ending["start_time"]
                }
            }

        else
            nil
        end

    end
    result.select{|c| c != nil}
end

def addCommitShasToGitInputs(inputs, gitInputKey)
    inputsWithShas = inputs.map do |input|
        gitInfo = input[gitInputKey]
        shas = gitInfo["version"]["ref"]
        input["shas"] = shas
        input
    end
    inputsWithShas
end

def printCycleTimeByCommits(pipeline, cycle)
    buildJob = cycle["start_job"]["name"]
    prodJob = cycle["end_job"]["name"]

    puts "\nPipeline: ".light_blue + "#{pipeline} "
    puts "Cycle: ".light_blue + "#{buildJob} >> #{prodJob}"

    puts "Collecting data from #{$baseUrl}...".light_black
    buildInputs = addCommitShasToGitInputs(
        getInputs(pipeline, buildJob, cycle["start_job"]["git_input"], {"max" => nil}),
        cycle["start_job"]["git_input"])
    prodInputs = addCommitShasToGitInputs(
        getInputs(pipeline, prodJob, cycle["end_job"]["git_input"], {"max" => nil}),
        cycle["end_job"]["git_input"])
    cycles = getCycles(buildInputs, prodInputs)

    durations = cycles.map{|c| c["duration"]}
    puts "AVERAGE: ".cyan + "#{readableDuration(average(durations))}"
    puts "MEDIAN: ".cyan + "#{readableDuration(median(durations))}"

    throughput = cycles.length.to_f / buildInputs.length.to_f * 100
    throughputText = "#{throughput.round(1)}% (#{cycles.length} of #{buildInputs.length})"
    if throughput > 50
        puts "THROUGHPUT: ".cyan + throughputText
    else
        puts "THROUGHPUT: ".cyan + throughputText.red
    end

    latestCompletedCycle = cycles.max_by{ |c| c["end"]["time"] }
    timeSinceLastCycle = Time.now.to_i - latestCompletedCycle["end"]["time"]
    puts "LAST DEPLOY: ".cyan + "#{readableDuration(timeSinceLastCycle)}"

    undeployedChanges = buildInputs.select{ |b| b["start_time"] > latestCompletedCycle["end"]["time"] }
    earliestUndeployedChange = undeployedChanges.min_by{ |b| b["start_time"] }
    if earliestUndeployedChange
        timeUndeployed = Time.now.to_i - earliestUndeployedChange["start_time"]
        puts "OLDEST UNDEPLOYED CHANGE:".cyan + " #{readableDuration(timeUndeployed)} (#{earliestUndeployedChange["jobName"]}::#{earliestUndeployedChange["name"]})"
    else
        puts "OLDEST UNDEPLOYED CHANGE: ".cyan + "none"
    end

    # cycles.each do |c|
    #     durationReadable = readableDuration(c["duration"])
    #     puts "#{c["shas"]}"\
    #         "  |  #{durationReadable}"\
    #         "  |  #{c["start"]["name"]} ##{c["start"]["number"]} #{readableDateTime(c["start"]["time"])}"\
    #         "  |  #{c["end"]["name"]} ##{c["end"]["number"]} #{readableDateTime(c["end"]["time"])}"
    # end
end

printCycleTimeByCommits("access-management", {
    "start_job" => { "name" => "bump-version", "git_input" => "access-management-git"},
    "end_job" => { "name" => "agent-integration-tests", "git_input" => "access-management-git"}
    }
)

# TODO: Failure rate
# TODO: MTTR
