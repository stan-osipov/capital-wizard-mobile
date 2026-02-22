//
//  ServiceManager.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

protocol Service { }

/*
 Service manager that store application services that provide easy access to them
 */
class ServiceManager {
    
    static var shared = ServiceManager()
    
    private var services: Array<Service> = Array<Service>()
    
    func register<T: Service>(_ service: T) {
        services.append(service)
    }
    
    func getService<T: Service>() -> T? {
        services.first(where: { type(of:$0) == T.self }) as? T
    }
}
