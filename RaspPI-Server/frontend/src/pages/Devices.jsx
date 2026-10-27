import { useState } from "react"
import SmartHomeCard from "../components/SmartHomeCard"
import { Lightbulb, Thermometer, Lock, Mic } from "lucide-react"
import { Progress } from "@/components/ui/progress"

function Devices() {

  const [devices, setDevices] = useState([
    { id: 1, location: "Living Room", isOn: true },
  ])

  function toggleDevice(id, checked) {
    setDevices(prevDevices =>
      prevDevices.map(device =>
        device.id === id
          ? { ...device, isOn: checked }
          : device
      )
    )
  }

  const activeDevices = devices.filter(device => device.isOn).length
  const totalDevices = devices.length
  const progress = totalDevices > 0
    ? (activeDevices / totalDevices) * 100
    : 0
    
    return (
        <div className="space-y-2">
            
            <h3 className="text-xl font-semibold text-white">Smart Home</h3>

            <p className="text-xs text-[#a35b89]">
                {activeDevices} of {totalDevices} active
            </p>

            <Progress value={progress} className="h-1 bg-[#39212e] [&_[data-slot=progress-indicator]]:bg-[#ef6cba]"/>
        
            <div className="grid grid-cols-6 p-4 gap-4">

                {devices.map(device => (

                    <SmartHomeCard
                        key={device.id}
                        icon={Lightbulb}
                        location={device.location}
                        isOn={device.isOn}
                        color="#ef6cba"
                        onToggle={checked => toggleDevice(device.id, checked)}
                    />
                ))}

            </div>

        </div> 
    )
}

export default Devices