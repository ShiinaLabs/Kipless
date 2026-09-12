import Foundation

let listener = NSXPCListener(machServiceName: "com.kaoru.kipless.lidsleep")
let delegate = SleepHelperListener()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
