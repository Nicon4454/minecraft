java -Xmx4G -Xms4G -XX:ReservedCodeCacheSize=512m -XX:NewRatio=4 -XX:SurvivorRatio=3 -XX:TargetSurvivorRatio=80 -XX:MaxTenuringThreshold=8 -XX:+UseParNewGC -XX:+UseConcMarkSweepGC -XX:SoftRefLRUPolicyMSPerMB=0 -XX:MaxGCPauseMillis=20 -XX:GCPauseIntervalMillis=250 -XX:MaxGCMinorPauseMillis=7 -XX:+CMSClassUnloadingEnabled -XX:+ExplicitGCInvokesConcurrentAndUnloadsClasses -XX:+UseCMSInitiatingOccupancyOnly -XX:CMSInitiatingOccupancyFraction=50 -XX:+BindGCTaskThreadsToCPUs -XX:+TieredCompilation -XX:Tier0ProfilingStartPercentage=0 -XX:Tier3InvocationThreshold=3 -XX:Tier3MinInvocationThreshold=2 -XX:Tier3CompileThreshold=2 -XX:Tier3BackEdgeThreshold=10 -XX:Tier4InvocationThreshold=4 -XX:Tier4MinInvocationThreshold=3 -XX:Tier4CompileThreshold=2 -XX:Tier4BackEdgeThreshold=8 -XX:TieredCompileTaskTimeout=5000 -XX:Tier3DelayOn=50 -XX:Tier3DelayOff=25 -XX:+UseFastEmptyMethods -XX:-DontCompileHugeMethods -XX:+AlwaysCompileLoopMethods -XX:+CICompilerCountPerCPU -XX:+UseStringCache -XX:+UseNUMA -jar forge-1.10.2-12.18.3.2511-universal.jar nogui