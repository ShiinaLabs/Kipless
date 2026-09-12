import Foundation

let listener = NSXPCListener(machServiceName: "com.kaoru.kipless.sleep-helper")
let delegate = SleepHelperListener()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
