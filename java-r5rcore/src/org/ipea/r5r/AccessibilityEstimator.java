package org.ipea.r5r;

import com.conveyal.r5.OneOriginResult;
import com.conveyal.r5.analyst.FreeFormPointSet;
import com.conveyal.r5.analyst.PointSet;
import com.conveyal.r5.analyst.TravelTimeComputer;
import com.conveyal.r5.analyst.cluster.RegionalTask;
import com.conveyal.r5.api.util.LegMode;
import com.conveyal.r5.profile.StreetMode;
import com.conveyal.r5.transit.TransportNetwork;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.text.ParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ForkJoinPool;

public class AccessibilityEstimator extends R5MultiDestinationProcess {

    private FreeFormPointSet destinationPoints;

    public AccessibilityEstimator(ForkJoinPool threadPool, TransportNetwork transportNetwork, RoutingProperties routingProperties) {
        super(threadPool, transportNetwork, routingProperties);
        destinationPoints = null;
    }

    @Override
    public List<LinkedHashMap<String, ArrayList<Object>>> run() throws ExecutionException, InterruptedException {
        buildDestinationPointSet();
        return super.run();
    }

    private void buildDestinationPointSet() {
        ByteArrayOutputStream dataStream = new ByteArrayOutputStream();
        DataOutputStream pointStream = new DataOutputStream(dataStream);

        try {
            pointStream.writeInt(toIds.length);
            for (String toId : toIds) {
                pointStream.writeUTF(toId);
            }
            for (double toLat : toLats) {
                pointStream.writeDouble(toLat);
            }
            for (double toLon : toLons) {
                pointStream.writeDouble(toLon);
            }
            for (int opportunity : opportunities) {
                pointStream.writeDouble(opportunity);
            }
        } catch (IOException e) {
            e.printStackTrace();
        }

        ByteArrayInputStream pointsInput = new ByteArrayInputStream(dataStream.toByteArray());

        try {
            destinationPoints = new FreeFormPointSet(pointsInput);
        } catch (IOException e) {
            e.printStackTrace();
        }

        if (!this.directModes.isEmpty()) {
            for (LegMode mode : this.directModes) {
                transportNetwork.linkageCache.getLinkage(destinationPoints, transportNetwork.streetLayer, StreetMode.valueOf(mode.toString()));
            }
        }
    }

    @Override
    protected LinkedHashMap<String, ArrayList<Object>> runProcess(int index) throws ParseException {
        RegionalTask request = buildRequest(index);

        request.percentiles = this.routingProperties.percentiles;
        request.recordAccessibility = true;
        request.recordTimes = false;

        TravelTimeComputer computer = new TravelTimeComputer(request, transportNetwork);
        OneOriginResult travelTimeResults = computer.computeTravelTimes();
        RDataFrame travelTimesTable = buildDataFrameStructure(fromIds[index]);
        populateDataFrame(travelTimeResults, travelTimesTable);

        if (travelTimesTable.nRow() > 0) {
            return travelTimesTable.getDataFrame();
        } else {
            return null;
        }
    }

    private void populateDataFrame(OneOriginResult travelTimeResults, RDataFrame travelTimesTable) {
        int[][][] accessibility = travelTimeResults.accessibility.getIntValues();

        int nPercentiles = routingProperties.percentiles.length;
        int nCutoffs = routingProperties.cutoffs.length;


        for (int p = 0; p < nPercentiles; p++) {
            for (int c = 0; c < nCutoffs; c++) {
                travelTimesTable.append();
                travelTimesTable.set("percentile", routingProperties.percentiles[p]);
                travelTimesTable.set("cutoff", routingProperties.cutoffs[c]);
                travelTimesTable.set("accessibility", accessibility[0][p][c]);
            }
        }
    }

    private RDataFrame buildDataFrameStructure(String fromId) {
        // Build return table
        RDataFrame travelTimesTable = new RDataFrame();
        travelTimesTable.addStringColumn("from_id", fromId);
        travelTimesTable.addIntegerColumn("percentile", 0);
        travelTimesTable.addIntegerColumn("cutoff", 0);
        travelTimesTable.addIntegerColumn("accessibility", 0);

        return travelTimesTable;
    }

    @Override
    protected RegionalTask buildRequest(int index) throws ParseException {
        RegionalTask request = super.buildRequest(index);

        request.destinationPointSets = new PointSet[1];
        request.destinationPointSets[0] = destinationPoints;

        return request;
    }

}
