//
//  AnnotationController.swift
//  apple_maps_flutter
//
//  Created by Luis Thein on 09.09.19.
//

import Foundation
import MapKit


extension AppleMapController: AnnotationDelegate {
        
    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
          if let flutterAnnotation = view.annotation as? FlutterAnnotation {
              switch newState {
              case .ending, .canceling:
                  view.dragState = .none
                  flutterAnnotation.coordinate = view.annotation?.coordinate ?? flutterAnnotation.coordinate
                  // Invoke the Flutter method "annotation#onDragEnd"
                  let coordinate = flutterAnnotation.coordinate
           
                  self.channel.invokeMethod("annotation#onDragEnd", arguments: ["annotationId": flutterAnnotation.id!, "position": [coordinate.latitude,coordinate.longitude]])
              default:
                  break
              }
          }
      }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)  {
        if let annotation: FlutterAnnotation = view.annotation as? FlutterAnnotation  {
            self.currentlySelectedAnnotation = annotation.id
            if !annotation.selectedProgrammatically {
                if !self.isAnnotationInFront(zIndex: annotation.zIndex) {
                    self.moveToFront(annotation: annotation)
                   
                }
                self.onAnnotationClick(annotation: annotation)
            } else {
                annotation.selectedProgrammatically = false
            }
           
            if annotation.infoWindowConsumesTapEvents {
                let tapGestureRecognizer = InfoWindowTapGestureRecognizer(target: self, action: #selector(onCalloutTapped))
                tapGestureRecognizer.annotationId = annotation.id
                tapGestureRecognizer.annotationView = view
                view.addGestureRecognizer(tapGestureRecognizer)
            }
        }
    }

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        } else if let flutterAnnotation = annotation as? FlutterAnnotation {
            return self.getAnnotationView(annotation: flutterAnnotation)
        }
        return nil
    }

    func getAnnotationView(annotation: FlutterAnnotation) -> MKAnnotationView {
        let identifier: String = annotation.id
        var annotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        let oldflutterAnnoation = annotationView?.annotation as? FlutterAnnotation
        if annotationView == nil || oldflutterAnnoation?.icon.iconType != annotation.icon.iconType {
            if #available(iOS 11.0, *), annotation.icon.iconType == IconType.MARKER {
                annotationView = getMarkerAnnotationView(annotation: annotation, id: identifier)
            } else if annotation.icon.iconType == .CUSTOM_FROM_ASSET || annotation.icon.iconType == .CUSTOM_FROM_BYTES {
                annotationView = getCustomAnnotationView(annotation: annotation, id: identifier)
            } else {
                annotationView = getPinAnnotationView(annotation: annotation, id: identifier)
            }
        }
        guard annotationView != nil else {
            return FlutterAnnotationView()
        }
        annotationView!.annotation = annotation
        // If annotation is not visible set alpha to 0 and don't let the user interact with it
        if !annotation.isVisible! {
            

            UIView.animate(withDuration: 0.32) {
                annotationView!.canShowCallout = false
                annotationView!.alpha = CGFloat(0.0)
                annotationView!.isDraggable = false
            }

            return annotationView!
        }
        if annotation.icon.iconType != .MARKER {
            self.initInfoWindow(annotation: annotation, annotationView: annotationView!)
            if annotation.icon.iconType != .PIN {
                let x = (0.5 - annotation.anchor.x) * Double(annotationView!.frame.size.width)
                let y = (0.5 - annotation.anchor.y) * Double(annotationView!.frame.size.height)
                annotationView!.centerOffset = CGPoint(x: x, y: y)
            }
        }
        annotationView!.canShowCallout = true
        annotationView!.alpha = CGFloat(annotation.alpha ?? 1.00)
        annotationView!.isDraggable = annotation.isDraggable ?? false

        return annotationView!
    }

    func annotationsToAdd(annotations: NSArray) {
        for annotation in annotations {
            let annotationData: Dictionary<String, Any> = annotation as! Dictionary<String, Any>
            addAnnotation(annotationData: annotationData)
        }
    }

    func annotationsToChange(annotations: NSArray) {
        let oldAnnotations: [MKAnnotation] = self.mapView.annotations
        for annotation in annotations {
            let annotationData: Dictionary<String, Any> = annotation as! Dictionary<String, Any>
            if let annotationToChange = oldAnnotations.filter({($0 as? FlutterAnnotation)?.id == annotationData["annotationId"] as? String})[0] as? FlutterAnnotation {
                let newAnnotation = FlutterAnnotation.init(fromDictionary: annotationData, registrar: registrar)
                if annotationToChange != newAnnotation {
                    if !annotationToChange.wasDragged {
                        updateAnnotation(annotation: newAnnotation)
                    } else {
                        annotationToChange.wasDragged = false
                    }
                }
            }
        }
    }
    
    func annotationsIdsToRemove(annotationIds: NSArray) {
        for annotationId in annotationIds {
            if let _annotationId: String = annotationId as? String {
                removeAnnotation(id: _annotationId, withAnimate: true)
            }
        }
    }

    func removeAllAnnotations() {
        self.mapView.removeAnnotations(self.mapView.annotations)
    }

    func onAnnotationClick(annotation: MKAnnotation) {
        if let flutterAnnotation: FlutterAnnotation = annotation as? FlutterAnnotation {
            if(flutterAnnotation.isDraggable ?? true) {
                flutterAnnotation.wasDragged = true
            }
            channel.invokeMethod("annotation#onTap", arguments: ["annotationId" : flutterAnnotation.id])
        }
    }
    
    @objc func onAnnotationClickGesture(with annotationId: String) {
            channel.invokeMethod("annotation#onTap", arguments: ["annotationId" : annotationId])
    }

    func selectAnnotation(with id: String) {
        if let annotation: FlutterAnnotation = self.getAnnotation(with: id) {
            annotation.selectedProgrammatically = true
            self.mapView.selectAnnotation(annotation, animated: true)
        }
    }
    

    func hideAnnotation(with id: String) {
        if let annotation: FlutterAnnotation = self.getAnnotation(with: id) {
            self.mapView.deselectAnnotation(annotation, animated: true)
        }
    }

    func isAnnotationSelected(with id: String) -> Bool {
        return self.mapView.selectedAnnotations.contains(where: { annotation in return self.getAnnotation(with: id) == (annotation as? FlutterAnnotation)})
    }


    private func removeAnnotation(id: String, withAnimate: Bool = false) {
        
   
        
        if let flutterAnnotation: FlutterAnnotation = self.getAnnotation(with: id) {
            
            if(withAnimate == false){
                self.mapView.removeAnnotation(flutterAnnotation)
                return
            }
            
            // Find the annotation view for the given annotation
            guard let annotationView = self.mapView.view(for: flutterAnnotation) else {
                   // If the view isn't available, simply remove the annotation
                   self.mapView.removeAnnotation(flutterAnnotation)
                   return
               }
               
               // Animate scaling down the annotation view
               UIView.animate(withDuration: 0.3, animations: {
                   annotationView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                   annotationView.alpha = 0 // Optional: Fade out for a smoother effect
               }) { _ in
                   // Remove the annotation after the animation completes
                   self.mapView.removeAnnotation(flutterAnnotation)
               }
            
              
        }
    }

    private func initInfoWindow(annotation: FlutterAnnotation, annotationView: MKAnnotationView) {
        let x = self.getInfoWindowXOffset(annotationView: annotationView, annotation: annotation)
        let y = self.getInfoWindowYOffset(annotationView: annotationView, annotation: annotation)
        annotationView.calloutOffset = CGPoint(x: x, y: y)
        if #available(iOS 9.0, *) {
            let lines = annotation.subtitle?.split(whereSeparator: { $0.isNewline })
            if lines != nil {
                let customCallout = UIStackView()
                customCallout.axis = .vertical
                customCallout.alignment = .fill
                customCallout.distribution = .fill
                for line in lines! {
                    let subtitle = UILabel()
                    subtitle.text = String(line)
                    customCallout.addArrangedSubview(subtitle)
                }
                annotationView.detailCalloutAccessoryView = customCallout
            }
        }
    }

    @objc func onCalloutTapped(infoWindowTap: InfoWindowTapGestureRecognizer) {
        if infoWindowTap.annotationId != nil && self.currentlySelectedAnnotation == infoWindowTap.annotationId! {
            self.channel.invokeMethod("infoWindow#onTap", arguments: ["annotationId": infoWindowTap.annotationId])
        }
        if infoWindowTap.annotationView != nil && self.currentlySelectedAnnotation != infoWindowTap.annotationId! {
            infoWindowTap.annotationView?.removeGestureRecognizer(infoWindowTap)
        }
    }

    private func getAnnotation(with id: String) -> FlutterAnnotation? {
        return self.mapView.annotations.filter { annotation in return (annotation as? FlutterAnnotation)?.id == id }.first as? FlutterAnnotation
    }

    private func annotationExists(with id: String) -> Bool {
        return self.getAnnotation(with: id) != nil
    }

    private func addAnnotation(annotationData: Dictionary<String, Any>) {
        let annotation: FlutterAnnotation = FlutterAnnotation(fromDictionary: annotationData, registrar: registrar)
        self.addAnnotation(annotation: annotation)
    }
    
    public func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        for annotationView in views {
            // Save the original alpha value
            let originalAlpha = annotationView.alpha

            // Start with the annotation view fully transparent
            annotationView.alpha = 0

            // Apply a bounce animation to the transform property
            UIView.animateKeyframes(withDuration: 0.2, delay: 0, options: [], animations: {
                // Fade in
                annotationView.alpha = originalAlpha
                
          
                // Add bounce keyframes
                UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.2) {
                    annotationView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.2) {
                    annotationView.transform = .identity
                }
            }, completion: nil)
        }
    }

    /**
     Checks if an Annotation with the same id exists and removes it before adding if necessary
     - Parameter annotation: the FlutterAnnotation that should be added
     */
    private func addAnnotation(annotation: FlutterAnnotation) {
        if self.annotationExists(with: annotation.id) {
            self.removeAnnotation(id: annotation.id)
        }
        if annotation.zIndex == -1 {
            annotation.zIndex = self.getNextAnnotationZIndex()
            channel.invokeMethod("annotation#onZIndexChanged", arguments: ["annotationId": annotation.id!, "zIndex": annotation.zIndex])
        }
        UIView.animate(withDuration: 0.32) {
            self.mapView.addAnnotation(annotation)
        }
    }

    private func updateAnnotation(annotation: FlutterAnnotation) {
        guard let oldAnnotation = self.getAnnotation(with: annotation.id) else {
            print("No existing annotation found for id: \(annotation.id)")
            return
        }
        
        // Check if zIndex has changed
        let zIndexChanged = oldAnnotation.zIndex != annotation.zIndex
        
//        if zIndexChanged {
//
//            oldAnnotation.zIndex = annotation.zIndex
//            // Re-add the annotation
//           self.addAnnotation(annotation:   oldAnnotation)
//            
//           // self.selectAnnotation(with: oldAnnotation.id)
//        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Retrieve the annotation view (after re-adding if zIndex changed)

            
            // Perform the animations
            UIView.animate(withDuration: 0.32) {
                
                // Update properties without removing the annotation
                oldAnnotation.coordinate = annotation.coordinate
                oldAnnotation.title = annotation.title
                oldAnnotation.subtitle = annotation.subtitle
                oldAnnotation.image = annotation.image
                oldAnnotation.icon = annotation.icon
                oldAnnotation.anchor = annotation.anchor
                oldAnnotation.alpha = annotation.alpha
                oldAnnotation.isVisible = annotation.isVisible
                
                
                guard let updatedView = self.mapView.view(for: oldAnnotation) else {
                    print("No view found for annotation id: \(annotation.id)")
                    return
                }
                
                // Update the annotation view properties
                updatedView.alpha = (annotation.isVisible ?? true) ? CGFloat(annotation.alpha ?? 1.0) : 0
                updatedView.isHidden = !(annotation.isVisible ?? true)
                updatedView.image = self.getAnnotationView(annotation: annotation).image
                updatedView.detailCalloutAccessoryView = self.getAnnotationView(annotation: annotation).detailCalloutAccessoryView
                updatedView.isDraggable = annotation.isDraggable ?? false
            }
        }
    }

    private func getNextAnnotationZIndex() -> Double {
        let mapViewAnnotations = self.mapView.getMapViewAnnotations()
        if mapViewAnnotations.isEmpty {
            return 0;
        }
        return (mapViewAnnotations.last??.zIndex ?? 0) + 1
    }

    private func isAnnotationInFront(zIndex: Double) -> Bool {
        return (self.mapView.getMapViewAnnotations().last??.zIndex ?? 0) == zIndex
    }

    private func getPinAnnotationView(annotation: FlutterAnnotation, id: String) -> MKPinAnnotationView {
        var pinAnnotationView: MKPinAnnotationView
        if #available(iOS 11.0, *) {
            self.mapView.register(MKPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
            pinAnnotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation) as! MKPinAnnotationView
        } else {
            pinAnnotationView = MKPinAnnotationView.init(annotation: annotation, reuseIdentifier: id)
        }
        pinAnnotationView.layer.zPosition = annotation.zIndex

        if let hueColor: Double = annotation.icon.hueColor {
            pinAnnotationView.pinTintColor = UIColor.init(hue: hueColor, saturation: 1, brightness: 1, alpha: 1)
        }

        return pinAnnotationView
    }

    @available(iOS 11.0, *)
    private func getMarkerAnnotationView(annotation: FlutterAnnotation, id: String) -> FlutterMarkerAnnotationView {
        self.mapView.register(FlutterMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
        let markerAnnotationView: FlutterMarkerAnnotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation) as! FlutterMarkerAnnotationView
        markerAnnotationView.stickyZPosition = annotation.zIndex

        if let hueColor: Double = annotation.icon.hueColor {
            markerAnnotationView.markerTintColor = UIColor.init(hue: hueColor, saturation: 1, brightness: 1, alpha: 1)
        }

        return markerAnnotationView
    }

    private func getCustomAnnotationView(annotation: FlutterAnnotation, id: String) -> FlutterAnnotationView {
        let annotationView: FlutterAnnotationView
        if #available(iOS 11.0, *) {
            self.mapView.register(FlutterAnnotationView.self, forAnnotationViewWithReuseIdentifier: id)
            annotationView = self.mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation) as! FlutterAnnotationView
        } else {
            annotationView = FlutterAnnotationView(annotation: annotation, reuseIdentifier: id)
        }
        annotationView.image = annotation.icon.image
        annotationView.stickyZPosition = annotation.zIndex
        return annotationView
    }

    private func getInfoWindowXOffset(annotationView: MKAnnotationView, annotation: FlutterAnnotation) -> CGFloat {
        if annotation.icon.iconType == .PIN {
            return annotationView.frame.origin.x - (annotationView.frame.origin.x * CGFloat(annotation.calloutOffset.x))
        }
        return annotationView.frame.origin.x + (annotationView.frame.width * CGFloat(annotation.calloutOffset.x))
    }

    private func getInfoWindowYOffset(annotationView: MKAnnotationView, annotation: FlutterAnnotation) -> CGFloat {
        return annotationView.frame.height * CGFloat(annotation.calloutOffset.y)
    }

    private func moveToFront(annotation: FlutterAnnotation) {
        let id: String = annotation.id
        annotation.zIndex = self.getNextAnnotationZIndex()
        channel.invokeMethod("annotation#onZIndexChanged", arguments: ["annotationId": id, "zIndex": annotation.zIndex])
        self.addAnnotation(annotation: annotation)
    }
}

class InfoWindowTapGestureRecognizer: UITapGestureRecognizer {
    var annotationView: UIView?
    var annotationId: String?
}
